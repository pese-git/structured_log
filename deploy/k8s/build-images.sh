#!/usr/bin/env bash
#
# Builds the server and admin-client images for a Kubernetes deployment —
# the same two Dockerfiles deploy/deploy.sh uses for Docker Compose, just
# without a compose file to build them for you.
#
#   ./build-images.sh                       # build locally, tag :local
#   ./build-images.sh --load minikube       # build, then load into minikube
#   ./build-images.sh --load kind           # build, then load into a kind cluster
#   ./build-images.sh --push registry.example.com/structured-log --tag v1.2.3
#   ./build-images.sh --push … --platform linux/amd64
#   ./build-images.sh --push … --server-repo backend --web-repo frontend
#   ./build-images.sh --push … --tag "$(git rev-parse --short HEAD)" --tag latest
#
# `--platform` matters more than it looks. Without it Docker builds for the
# machine it runs on, and this repository is developed on Apple Silicon
# while the clusters it deploys to are `linux/amd64` — so a push from a
# laptop lands an arm64 image under the tag a node will try to pull, and
# the failure surfaces as `exec format error` in a crash loop rather than
# anything about architecture. Nothing in the pipeline would have said so:
# `docker push` is happy, the registry is happy, the manifest is simply for
# the wrong machine.
#
# `--tag` may be given more than once, because "the commit, and also
# `latest`" is one decision and two names for one image. Doing it in two
# runs builds twice, and two builds of the same commit are not the same
# bytes — the web bundle alone is not reproducible — so `latest` would
# end up pointing at an image nobody ever tested. Repeated `--tag`
# produces one image wearing every name.
#
# `--server-repo`/`--web-repo` exist because a registry's layout is the
# registry's business: the defaults spell the names this repository uses
# for a local build, and a registry that groups them differently (this
# project's own Harbor keeps them as `backend` and `frontend`) can say so
# without the script having to know about any particular one.
#
# Run from this directory. Everything it needs beyond Docker is the
# Flutter SDK the repository already pins (via FVM) — there is no
# official Flutter Docker image, and a third-party one is not something
# to put in a deployment path unexamined (see the web Dockerfile).

set -euo pipefail

cd "$(dirname "$0")"
REPO_ROOT="$(cd ../.. && pwd)"

FLUTTER="$REPO_ROOT/.fvm/flutter_sdk/bin/flutter"
CLIENT="$REPO_ROOT/frontend/structured_log_admin_client"

registry=""
tags=()
load=""
platform=""
server_repo="structured-log-server"
web_repo="structured-log-web"

while [ $# -gt 0 ]; do
  case "$1" in
    --push) registry="$2"; shift 2 ;;
    --tag) tags+=("$2"); shift 2 ;;
    --load) load="$2"; shift 2 ;;
    --platform) platform="$2"; shift 2 ;;
    --server-repo) server_repo="$2"; shift 2 ;;
    --web-repo) web_repo="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

# `:local` is what the kustomize overlays name, so it stays the default —
# but only when nothing was asked for, since appending to a list the
# caller filled would tag every build `local` as well.
if [ ${#tags[@]} -eq 0 ]; then
  tags=("local")
fi

if [ -n "$registry" ] && [ -n "$load" ]; then
  echo "error: --push and --load are alternatives, not both — a pushed" >&2
  echo "       image is pulled by the cluster from the registry; a loaded" >&2
  echo "       one never leaves the local machine, there's nothing to pull." >&2
  exit 2
fi

# A foreign-architecture image has nowhere to go but a registry: `buildx`
# cannot hand one to the local daemon, and a cluster on this machine runs
# the machine's own architecture anyway. Refusing the combination here says
# that plainly, rather than letting buildx fail further in with its own
# wording about exporters.
if [ -n "$platform" ] && [ -z "$registry" ]; then
  echo "error: --platform needs --push — an image built for another" >&2
  echo "       architecture cannot be loaded into this machine's Docker" >&2
  echo "       daemon or into a local cluster, only pushed to a registry" >&2
  echo "       for a node of that architecture to pull." >&2
  exit 2
fi

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "error: $1 is required but was not found" >&2
    exit 1
  }
}

require docker

if [ ! -x "$FLUTTER" ]; then
  echo "error: no Flutter SDK at $FLUTTER" >&2
  echo "       run 'fvm install' from the repository root first" >&2
  exit 1
fi

# Every name each image is to be known by. The first is the one the
# closing hints quote: a run tagging both a commit and `latest` means the
# commit, with `latest` as the moving alias for it.
prefix="${registry:+$registry/}"
server_images=()
web_images=()
for t in "${tags[@]}"; do
  server_images+=("${prefix}${server_repo}:${t}")
  web_images+=("${prefix}${web_repo}:${t}")
done
server_image="${server_images[0]}"
web_image="${web_images[0]}"

# Same reasoning as deploy.sh: an empty base URL means the client is
# served from the same origin as the API and every request goes out
# relative to the page — the point of the single-origin architecture
# this whole deployment exists to preserve (see README.md).
echo "==> building the admin client (web)"
(
  cd "$CLIENT"
  # `--no-web-resources-cdn` keeps the rendering engine local. Without it the
  # bundle boots CanvasKit from `www.gstatic.com` and fetches Roboto from
  # `fonts.gstatic.com` at runtime — so the panel calls Google on every load,
  # fails outright on a host that cannot reach it, and cannot be served under
  # a `script-src 'self'` policy. The engine is already in the bundle
  # (`build/web/canvaskit/`); this is what makes it the one that is used.
  "$FLUTTER" build web --release --no-web-resources-cdn \
    --dart-define=STRUCTURED_LOG_BASE_URL=
)

# One image, built the way this invocation asked for.
#
# With `--platform` the build goes through `buildx` and pushes from the
# same command, because that is the only way out for a cross-architecture
# image: `buildx` has no exporter that puts one in the local daemon, so
# building first and pushing after — the shape the rest of this script
# uses — has no step in between where the image could live.
build_image() {
  dockerfile="$1"
  shift
  names=("$@")

  echo "==> building ${names[*]}${platform:+ ($platform)}"

  args=()
  for name in "${names[@]}"; do
    args+=(-t "$name")
  done

  if [ -n "$platform" ]; then
    docker buildx build --platform "$platform" \
      -f "$dockerfile" "${args[@]}" --push "$REPO_ROOT"
  else
    docker build -f "$dockerfile" "${args[@]}" "$REPO_ROOT"
  fi
}

build_image "$REPO_ROOT/backend/structured_log_server/Dockerfile" \
  "${server_images[@]}"
build_image "$REPO_ROOT/frontend/structured_log_admin_client/Dockerfile" \
  "${web_images[@]}"

if [ -n "$registry" ]; then
  # Already in the registry when `--platform` was given: that build pushed
  # as it went, and pushing again would upload nothing and say so.
  if [ -z "$platform" ]; then
    echo "==> pushing to $registry"
    for name in "${server_images[@]}" "${web_images[@]}"; do
      docker push "$name"
    done
  fi
  echo
  echo "Set these in your kustomization (images: transformer, or"
  echo "'kustomize edit set image'):"
  echo "  structured-log-server:local -> $server_image"
  echo "  structured-log-web:local    -> $web_image"
elif [ -n "$load" ]; then
  case "$load" in
    minikube)
      require minikube
      echo "==> loading into minikube"
      for name in "${server_images[@]}" "${web_images[@]}"; do
        minikube image load "$name"
      done
      ;;
    kind)
      require kind
      echo "==> loading into kind"
      for name in "${server_images[@]}" "${web_images[@]}"; do
        kind load docker-image "$name"
      done
      ;;
    *)
      echo "error: --load must be 'minikube' or 'kind', got '$load'" >&2
      exit 2
      ;;
  esac
  echo
  echo "Images are on the cluster's node(s) now. Local-only images need"
  echo "imagePullPolicy: Never (or IfNotPresent) — a registry-pulled tag"
  echo "otherwise fails to pull with ImagePullBackOff. Set it directly on"
  echo "structured-log-server/structured-log-web in your overlay, or"
  echo "'kubectl set image ...' after applying."
else
  echo
  echo "Built locally as $server_image / $web_image — not pushed or"
  echo "loaded anywhere. A multi-node cluster's kubelet cannot pull an"
  echo "image that only exists on this machine's Docker daemon; use"
  echo "--push for a real cluster or --load minikube|kind for local testing."
fi
