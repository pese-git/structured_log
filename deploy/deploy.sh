#!/usr/bin/env bash
#
# Builds and starts the self-hosted deployment: the API, and the admin client
# served beside it on one origin.
#
#   ./deploy.sh              # build what changed and start
#   ./deploy.sh --rebuild    # rebuild both images from scratch
#
# Run from this directory. Everything it needs beyond Docker is the Flutter
# SDK the repository already pins.

set -euo pipefail

cd "$(dirname "$0")"
REPO_ROOT="$(cd .. && pwd)"

FLUTTER="$REPO_ROOT/.fvm/flutter_sdk/bin/flutter"
CLIENT="$REPO_ROOT/frontend/structured_log_admin_client"
SECRET_FILE="./secrets/jwt_signing_secret"

rebuild=""
for arg in "$@"; do
  case "$arg" in
    --rebuild) rebuild="--no-cache" ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "error: $1 is required but was not found" >&2
    exit 1
  }
}

require docker

if ! docker compose version >/dev/null 2>&1; then
  echo "error: docker compose v2 is required ('docker-compose' v1 will not do)" >&2
  exit 1
fi

if [ ! -x "$FLUTTER" ]; then
  echo "error: no Flutter SDK at $FLUTTER" >&2
  echo "       run 'fvm install' from the repository root first" >&2
  exit 1
fi

if [ ! -f .env ]; then
  echo "note: .env is missing; copying .env.example"
  cp .env.example .env
fi

# --- the signing secret -----------------------------------------------------
# Generated once and kept out of the environment and out of git: every access
# token the server has issued is verified with it, so replacing it signs
# everyone out, and leaking it lets anyone mint a token.
if [ ! -f "$SECRET_FILE" ]; then
  echo "note: generating $SECRET_FILE"
  mkdir -p "$(dirname "$SECRET_FILE")"
  # No trailing newline: the server reads the file verbatim, and a stray \n
  # would be part of the secret — harmless until someone copies the value out
  # of the file by hand and gets a different one.
  openssl rand -base64 48 | tr -d '\n' > "$SECRET_FILE"
  chmod 600 "$SECRET_FILE"
fi

# --- the client's web build -------------------------------------------------
# An empty base URL on purpose: the client is served from the same origin as
# the API, so every request goes out relative to the page and needs no host
# baked into the bundle. That is also what lets one image serve any domain.
echo "==> building the admin client (web)"
(
  cd "$CLIENT"
  "$FLUTTER" build web --release --dart-define=STRUCTURED_LOG_BASE_URL=
)

# --- images and containers --------------------------------------------------
echo "==> building images"
# shellcheck disable=SC2086
docker compose build $rebuild

echo "==> starting"
docker compose up -d

port="$(grep -E '^STRUCTURED_LOG_PUBLIC_PORT=' .env | cut -d= -f2)"
port="${port:-8080}"

echo
echo "up: http://localhost:$port"
echo
echo "On an empty database the server creates the first administrator and"
echo "prints a generated password once, as a warning. Read it with:"
echo
echo "  docker compose logs server | grep -i 'temporary password'"
echo
echo "It must be changed at first sign-in."
