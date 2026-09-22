#!/usr/bin/env bash
#
# Creates (or rotates) the Kubernetes Secrets the manifests in this
# directory expect — the JWT signing secret always, the PostgreSQL
# password only when the postgres overlay is in use. Deliberately
# separate from `kubectl apply -k`: a Secret's lifecycle (generate once,
# rotate is a disruptive action that signs everyone out — see
# README.md) shouldn't ride along with re-applying the rest of the stack
# on every deploy.
#
#   ./create-secrets.sh                 # JWT secret only (sqlite overlay)
#   ./create-secrets.sh --postgres       # JWT secret + a generated Postgres password
#   NAMESPACE=my-ns ./create-secrets.sh  # a namespace other than the default
#
# Safe to re-run: existing secrets are left untouched unless --rotate is
# passed explicitly, precisely so this can't be run by habit and
# accidentally sign out every session in the cluster.

set -euo pipefail

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "error: $1 is required but was not found" >&2
    exit 1
  }
}

require kubectl
require openssl

namespace="${NAMESPACE:-structured-log}"
with_postgres=""
rotate=""

while [ $# -gt 0 ]; do
  case "$1" in
    --postgres) with_postgres=1; shift ;;
    --rotate) rotate=1; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

context="$(kubectl config current-context 2>/dev/null || echo '(none)')"
echo "kubectl context: $context"
echo "namespace:        $namespace"
echo

# Idempotent, and deliberately not an error if it's missing: this script
# is meant to be safe to run *before* `kubectl apply -k`, not only after
# — a Deployment referencing a Secret that doesn't exist yet just sits
# ContainerCreating until it does, but there's no reason to make anyone
# discover that ordering by trial and error.
kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

create_or_skip() {
  local name="$1" key="$2" value="$3"
  if kubectl -n "$namespace" get secret "$name" >/dev/null 2>&1 && [ -z "$rotate" ]; then
    echo "secret/$name already exists in '$namespace' — leaving it alone (pass --rotate to replace it)"
    return
  fi
  if [ -n "$rotate" ] && kubectl -n "$namespace" get secret "$name" >/dev/null 2>&1; then
    echo "rotating secret/$name — every session using it will need to sign in again"
  fi
  kubectl -n "$namespace" create secret generic "$name" \
    --from-literal="$key=$value" \
    --dry-run=client -o yaml | kubectl apply -f -
}

# No trailing newline in the value: the server reads the mounted file
# verbatim, and a stray \n would become part of the secret.
create_or_skip structured-log-secrets jwt-secret "$(openssl rand -base64 48 | tr -d '\n')"

if [ -n "$with_postgres" ]; then
  create_or_skip postgres-secrets postgres-password "$(openssl rand -base64 24 | tr -d '\n')"
fi

echo
echo "Done. Apply the manifests next, e.g.:"
echo "  kubectl apply -k overlays/sqlite     # or overlays/postgres"
