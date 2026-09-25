# Kubernetes deployment

Self-hosted `structured_log` on Kubernetes: the same two images
[`deploy/`](../) builds for Docker Compose, as [Kustomize](https://kustomize.io/)
manifests instead — a `base/` shared by both storage backends, and one
overlay per backend (`overlays/sqlite/`, `overlays/postgres/`). No Helm,
no separate templating language — `kubectl` speaks Kustomize natively.

For the reasoning behind the non-obvious parts of this setup (why the
server can only ever run one replica, two real gotchas found while
building this), see
[docs/guides/admin-guide.md#kubernetes](../../docs/guides/admin-guide.md#kubernetes).
This file is the short, practical companion — hand-verified against a
local cluster (`minikube`, ingress-nginx) while writing it, not just
written from reading the config.

## Quick start

```bash
cd deploy/k8s

# Build both images and load them straight into a local cluster for
# testing — see "Building for a real cluster" below for anything else.
./build-images.sh --load minikube        # or: --load kind

./create-secrets.sh                      # generates the JWT signing secret
kubectl apply -k overlays/sqlite         # or: overlays/postgres

kubectl -n structured-log rollout status deployment/structured-log-server
kubectl -n structured-log logs deploy/structured-log-server | grep -i 'temporary password'
```

That last line is the generated first-administrator password, printed
once — capture it before it scrolls out of the log. It has to be
changed at first sign-in, same as every other deployment path.

Reach the admin client with `kubectl -n structured-log port-forward svc/web
8080:80` for a quick local check, or set up the bundled `Ingress`
properly (below) for anything real.

## What's here

```
base/                    # shared by both backends: namespace, the
                          # "server" Service, the web Deployment/Service,
                          # the Ingress
overlays/sqlite/          # + PVC, the server Deployment (SQLite-backed,
                          # strategy: Recreate)
overlays/postgres/        # + a minimal in-cluster PostgreSQL
                          # (StatefulSet), the server Deployment
                          # (PostgreSQL-backed)
build-images.sh           # builds/pushes/loads the two images
create-secrets.sh         # generates the Secrets the manifests expect
```

Pick exactly one overlay — `kubectl apply -k overlays/sqlite` **or**
`overlays/postgres`, never both against the same namespace.

## Building for a real cluster

`build-images.sh` with no flags just builds and tags locally
(`structured-log-server:local` / `structured-log-web:local`) — enough
for `--load minikube`/`--load kind`, not for anything else. A
multi-node cluster's kubelet pulls images from a registry; it cannot
see your laptop's Docker daemon:

```bash
./build-images.sh --push registry.example.com/structured-log --tag v1.2.3
```

then point the overlay at what was actually pushed — either edit the
`image:` lines in `overlays/*/server-deployment.yaml` and
`base/web-deployment.yaml` directly, or use Kustomize's own mechanism
for this instead of hand-editing:

```bash
cd overlays/sqlite   # or overlays/postgres
kustomize edit set image \
  structured-log-server:local=registry.example.com/structured-log/structured-log-server:v1.2.3 \
  structured-log-web:local=registry.example.com/structured-log/structured-log-web:v1.2.3
```

### Building for the cluster's architecture

`--platform` decides what the image is *for*, and leaving it out means
"for whatever this machine is". That is the wrong answer whenever they
differ — this repository is developed on Apple Silicon and deployed to
`linux/amd64` nodes — and nothing reports it: the build succeeds, the
push succeeds, and the node fails to start the container with `exec
format error`, which says nothing about architecture.

```bash
./build-images.sh --push registry.example.com/structured-log --tag v1.2.3 \
  --platform linux/amd64
```

A cross-architecture build goes out through `buildx` and pushes from the
same command, because there is nowhere else for it to go: `buildx` has no
exporter that hands such an image to the local Docker daemon. That is
also why `--platform` without `--push` is refused rather than quietly
building something unusable.

`--tag` may be given more than once. "The commit, and also `latest`" is
one decision and two names for one image, and running the script twice
would not give you that: two builds of the same commit are not the same
bytes — the web bundle alone is not reproducible — so `latest` would
point at an image nobody ever tested. Repeated `--tag` builds once and
applies every name to it.

```bash
./build-images.sh --push registry.example.com/structured-log \
  --platform linux/amd64 \
  --tag "$(git rev-parse --short HEAD)" --tag latest
```

The first `--tag` is the one the closing kustomize hint quotes: a run
tagging both a commit and `latest` means the commit, with `latest` as a
moving alias for it.

`--server-repo`/`--web-repo` name the repositories inside the registry,
for a registry that groups them differently from the local tags:

```bash
./build-images.sh --push harbor.example.com/structured-log --tag v1.2.3 \
  --platform linux/amd64 --server-repo backend --web-repo frontend
```

## Secrets

```bash
./create-secrets.sh              # JWT signing secret only (sqlite overlay)
./create-secrets.sh --postgres   # + a generated PostgreSQL password
```

Safe to re-run — an existing secret is left alone unless you pass
`--rotate` explicitly, precisely so this can't sign out every session
in the cluster by habit. If you already run PostgreSQL and skipped
`overlays/postgres/postgres-statefulset.yaml`, set
`STRUCTURED_LOG_DB_POSTGRES_PASSWORD` from your own secret instead —
`postgres-secrets`/`postgres-password` here is only for the bundled
in-cluster instance.

## The Ingress

`base/ingress.yaml` ships with a placeholder host
(`logs.example.com`) and two path rules — `/v1` straight to the
`server` Service, everything else to `web`. The `web` image doesn't
proxy anything itself (unlike the Docker Compose path, which needs its
own `proxy` container for exactly this split — see
[`deploy/proxy/`](../proxy/)); an Ingress already does it, so there's
nothing extra to run. Edit the `host:` field for your domain, or
override it per-overlay with a small Kustomize patch if you need
different hosts for `sqlite`/`postgres` environments. Requires an
ingress controller already installed in the cluster (`ingressClassName:
nginx` — swap it for whatever's actually there); this repository
doesn't install one for you.

## Uninstalling

```bash
kubectl delete -k overlays/sqlite        # or overlays/postgres
kubectl -n structured-log delete secret structured-log-secrets postgres-secrets --ignore-not-found
kubectl delete namespace structured-log  # also removes the PVC(s) — the data goes with it
```

## See also

- [docs/guides/admin-guide.md](../../docs/guides/admin-guide.md) — the
  full operator's guide: choosing a storage backend, retention/quotas,
  backups, security, upgrading, troubleshooting — Kubernetes included.
- [../](../) — the Docker Compose path, for a single-server deployment
  that doesn't need an orchestrator at all.
