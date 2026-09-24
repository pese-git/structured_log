# Administrator / DevOps Guide

*Читать на [русском](admin-guide.ru.md).*

For whoever deploys, configures, and keeps `structured_log_server`
running. If you're using the app day to day rather than operating it,
see the [User Guide](user-guide.md); if you're integrating your own
application with it, see the [Developer Guide](developer-guide.md).

## What you're running

One self-hosted service, `structured_log_server` — a single process,
no message broker, no external cache, and (with the default storage
backend) no separate database server either. Alongside it,
`structured_log_admin_client` is a web app that talks to the server
over its HTTP API; deploying both together, behind one nginx, is the
supported path and the one this guide walks through. Nothing stops you
from running the server alone and pointing a different client at its
API (see the [Developer Guide](developer-guide.md)), but the bundled
deployment is what's tested and documented end to end.

**Why one origin, and no cross-origin access by default.** The server
sends no `Access-Control-Allow-*` headers unless you explicitly turn
CORS on (below), which means a browser refuses to let the admin client
talk to it from a different host/port entirely — not a bug, a
deliberate default. Serving the client and the API behind the same
nginx origin (as the bundled `docker-compose.yml` does) sidesteps the
question entirely: every request the client makes is same-origin.
Enable `--cors-allowed-origins` only if you have a specific reason to
serve the client from elsewhere (local development against a
separately-hosted API, a different deployment topology you've thought
through).

## Quick start: Docker Compose

The fastest correct path, using what's checked into
[`deploy/`](../../deploy/):

```bash
cd deploy
cp .env.example .env    # edit if you want a non-default port/username
./deploy.sh
```

This builds the admin client's web bundle (with the Flutter SDK the
repository pins — nothing to install separately), builds both Docker
images, generates a random JWT (JSON Web Token) signing secret — the
key the server uses to sign every session token it issues — into
`deploy/secrets/jwt_secret` (once, on first run — git-ignored,
mounted read-only, never in an environment variable or a compose file
that could be committed), and starts three containers behind one nginx:

| Service | What it is |
|---|---|
| `server` | The API — not published to the host, reachable only through `proxy` |
| `web` | nginx: just the admin client's static files. Doesn't know `server` exists — not published to the host either |
| `proxy` | An off-the-shelf nginx that puts `web` and `server` behind the one origin the client is published on |

```bash
open http://localhost:8080    # or your STRUCTURED_LOG_PUBLIC_PORT
```

On an empty database the server creates the first administrator
automatically and prints a temporary password **once**, as a warning-level
log line — capture it before it scrolls out of view:

```bash
docker compose logs server | grep -i 'temporary password'
```

That account must change its password at first sign-in; every other
endpoint refuses it until then. See
[Bootstrapping the first administrator](#bootstrapping-the-first-administrator)
below for the alternatives (a password you choose, or disabling
auto-creation entirely).

```bash
docker compose logs -f server    # JSON lines, one request per line
docker compose ps                # container health, included
docker compose down              # stop; the data volume survives
docker compose down -v           # stop AND delete the database volume
```

`./deploy.sh` rebuilds whatever changed on a redeploy; `./deploy.sh
--rebuild` forces both images to build from scratch (useful after a
Dart/Flutter SDK bump, or when a layer cache looks stale).

## Running it without Docker

Everything above is Docker Compose convenience around two things you
can also run directly:

```bash
cd backend/structured_log_server
dart pub get
dart run build_runner build --delete-conflicting-outputs   # generates drift/freezed/router code

export STRUCTURED_LOG_JWT_SECRET="$(openssl rand -hex 32)"
dart run bin/server.dart serve --db-path=/var/lib/structured_log/logs.db
```

Requires the Dart SDK (3.0+) and nothing else for the default SQLite
backend. `dart compile exe bin/server.dart -o structured-log-server`
produces a standalone native binary if you'd rather not ship the SDK to
a production host — this is exactly what the Docker image's build
stage does internally. The admin client, if you're serving it yourself
outside the bundled nginx setup, is a static Flutter web build:

```bash
cd frontend/structured_log_admin_client
flutter build web --release --dart-define=STRUCTURED_LOG_BASE_URL=https://your-api-host
```

serve `build/web/` with any static file server, and see the CORS note
above if that host differs from the API's.

## Kubernetes

[`deploy/k8s/`](../../deploy/k8s/) has the actual manifests — a
Kustomize `base/` shared by both storage backends plus one overlay
each (`overlays/sqlite/`, `overlays/postgres/`), and two scripts
(`build-images.sh`, `create-secrets.sh`). This section is the reasoning
behind their non-obvious parts, hand-verified against a local cluster
(`minikube`, ingress-nginx) while writing it — for the actual
`kubectl`/`kustomize` commands, see
[deploy/k8s/README.md](../../deploy/k8s/README.md).

### Exactly one replica

The server must run as exactly one replica, always — this is not a
resource-sizing choice. Live-stream delivery (`GET /v1/logs/stream`)
is an in-process broadcast with no external pub/sub behind it (see
[architecture/live-streaming.md](../architecture/live-streaming.md)).
A second replica would have its own, separate broadcast, and a client
connected to one replica would silently miss log entries that a
load-balanced `POST /v1/logs` happened to land on the other. This holds
under *both* storage backends; moving to PostgreSQL does not change it
— both overlays' `server-deployment.yaml` fix `replicas: 1`. Scale the
**web** deployment (the admin client's static nginx) freely — it's
stateless, `base/web-deployment.yaml` runs it at 2 by default.

### Secrets path

Secrets mount at `/etc/structured-log/secrets`, deliberately not
`/run/secrets`. That path collides with Kubernetes' own default
service-account token mount
(`/var/run/secrets/kubernetes.io/serviceaccount` — `/run` and `/var/run`
are the same directory in the image). Mounting a `Secret` volume there
made the container fail to start at all in testing
(`unable to create mountpoint: read-only file system`).

### enableServiceLinks: false

Every pod spec sets `enableServiceLinks: false` — this avoids noise,
not a correctness problem. Kubernetes injects Docker-links-style
environment variables named after every Service visible to the pod
(`<SVC>_SERVICE_HOST`, `_PORT`, ...). A Service named `server` produces
variables prefixed `STRUCTURED_LOG_SERVER_...`, which collide with this
project's own `STRUCTURED_LOG_` prefix convention. The resolver already
tolerates this gracefully — an unrecognized `STRUCTURED_LOG_*` variable
only warns, never fails startup (see ["Configuration surface"](#configuration-surface)
above) — but there's no reason to invite the warning.

### SQLite overlay: Recreate strategy

The SQLite overlay sets `strategy: type: Recreate`, not the
`RollingUpdate` default. `Recreate` tears the old pod down before the
new one starts. Two pods briefly running together during a rolling
update would otherwise be two SQLite writers pointed at the same file
on the same `ReadWriteOnce` volume. Confirmed by tearing the pod down
directly (`kubectl delete pod -l app=structured-log-server`, not just a
rolling `apply`) in testing: the replacement pod came up against the
same PVC with no new "temporary password" line in its logs — the
bootstrap admin and every project already created survive a
reschedule, exactly as `ReadWriteOnce` is supposed to guarantee.

**PostgreSQL overlay** connects to the in-cluster `postgres` Service
(a minimal `StatefulSet`, `overlays/postgres/postgres-statefulset.yaml`)
by its short DNS name — or point
`STRUCTURED_LOG_DB_POSTGRES_HOST` at your own instance instead and skip
that file entirely. Verified the same way as the SQLite path: the
server resolved the Service and passed `/healthz` with no special
networking configuration beyond an ordinary `ClusterIP` Service.

### Ingress routing

The `Ingress` splits by path itself — `/v1` straight to the `server`
Service, everything else to `web`. Neither image knows the other
exists: `web` is a plain static-file server with no backend awareness
at all, and `server` has no idea anything proxies to it. That's
deliberate, not an oversight — the `web` image used to have `server`'s
address baked into its own nginx config, which meant it needed
`server` to be resolvable just to *start*, whether or not this
deployment's traffic ever actually reached it through that path
(found building exactly that: a three-way split with `site`, `web`,
and `server` each getting their own path off one Ingress, with `/v1`
already going straight to `server` — `web`'s internal proxy was dead
code that could still crash-loop the whole container). An `Ingress` is
already the layer whose job is knowing where every path goes; making
`web` duplicate that job was the bug, not a feature to preserve.

One origin, no CORS configuration needed anywhere in this setup —
same reasoning as the bundled Docker Compose deployment, which does
the identical split with a dedicated `proxy` container instead of an
`Ingress` (see [`deploy/proxy/`](../../deploy/proxy/)) since Compose
has no path-routing layer of its own.

Re-bootstrap an administrator on a non-empty database the same way the
[Docker Compose path does](#bootstrapping-the-first-administrator), via
a one-off `kubectl run`/`kubectl exec` invoking `create-admin` against
the same PVC or Postgres connection — there is no separate Kubernetes
`Job` manifest for this; it's the same CLI command as everywhere else.

## Choosing a storage backend

`--db-backend` picks between two, decided once at deploy time on an
**empty** database — this is not a runtime toggle, and there is no
built-in migration path from one to the other. Nothing about the HTTP
API, the data model, or what a client sees differs between them; only
the operational story does.

### SQLite (the default)

```bash
dart run bin/server.dart serve --db-backend=sqlite --db-path=/data/logs.db
# or simply: --db-path=/data/logs.db  (sqlite is the default backend)
```

One file, no separate service to run or monitor. WAL mode (SQLite's
write-ahead logging, which lets readers and a writer touch the database
concurrently) and a 5-second busy timeout are fixed, not configurable —
they exist specifically so a
second short-lived process (`create-admin`, below) can touch the same
file while the server is up without failing outright. Reads get their
own pool of extra connections beside the single writer
(`--db-read-pool-size`, default `2`, `0`–`16`) so a slow search doesn't
queue behind log ingestion; writes (ingestion, every management
mutation) always go through the one writer connection — this is a
deliberate non-goal to scale past, not an oversight.

**Right for:** a single-server deployment, low-to-moderate operational
overhead, and an operator who's comfortable with file-level backups
(below). This is what most deployments should start with.

### PostgreSQL

```bash
export STRUCTURED_LOG_DB_POSTGRES_PASSWORD='...'
dart run bin/server.dart serve \
  --db-backend=postgres \
  --db-postgres-host=db.internal \
  --db-postgres-database=structured_log \
  --db-postgres-username=structured_log
```

| Setting | Default | Notes |
|---|---|---|
| `--db-postgres-host` / `-port` / `-database` / `-username` | port `5432` | Required (except port) when this backend is selected |
| `STRUCTURED_LOG_DB_POSTGRES_PASSWORD` / `_FILE` | — | Secret: no CLI flag, same mounted-file convention as the JWT secret |
| `--db-postgres-pool-size` | `10` (1–64) | One pool, shared by reads and writes — PostgreSQL's own concurrent-writer model doesn't need SQLite's read/write split. `--db-read-pool-size` has no effect here; setting it away from its default only logs a warning at startup |
| `--db-postgres-ssl-mode` | `require` | `require` (encrypted, certificate not verified — the common case behind a managed provider's own network), `verify-full` (encrypted and verified), or `disable` (no TLS, for local development against an instance with none configured) |

**Right for:** an operator who already runs PostgreSQL and wants its
own backup/HA/monitoring tooling to cover log storage too, or who needs
PostgreSQL's native concurrent writers instead of SQLite's
single-writer-plus-WAL model at higher write volume.

**Docker Compose with PostgreSQL.** The bundled `deploy/docker-compose.yml`
ships with SQLite as its reference path. To run the same stand against
PostgreSQL instead, add a `docker-compose.override.yml` beside it
(Compose loads it automatically) — for example:

```yaml
services:
  server:
    environment:
      STRUCTURED_LOG_DB_BACKEND: postgres
      STRUCTURED_LOG_DB_POSTGRES_HOST: postgres
      STRUCTURED_LOG_DB_POSTGRES_DATABASE: structured_log
      STRUCTURED_LOG_DB_POSTGRES_USERNAME: structured_log
      STRUCTURED_LOG_DB_POSTGRES_PASSWORD_FILE: /run/secrets/postgres_password
      STRUCTURED_LOG_DB_POSTGRES_SSL_MODE: disable   # two containers, same private network
    volumes:
      - ./secrets/postgres_password:/run/secrets/postgres_password:ro
    depends_on:
      postgres:
        condition: service_healthy

  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: structured_log
      POSTGRES_PASSWORD_FILE: /run/secrets/postgres_password
      POSTGRES_DB: structured_log
    volumes:
      - pgdata:/var/lib/postgresql/data
      - ./secrets/postgres_password:/run/secrets/postgres_password:ro
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U structured_log -d structured_log"]
      interval: 5s
      timeout: 5s
      retries: 10

volumes:
  pgdata:
```

with a generated secret file at `deploy/secrets/postgres_password`
(same convention as `deploy/secrets/jwt_secret` — `openssl rand -base64
24 | tr -d '\n' > deploy/secrets/postgres_password && chmod 600
deploy/secrets/postgres_password`), then `./deploy.sh` as usual.

## Bootstrapping the first administrator

On a genuinely empty database (`users` table has zero rows), the server
creates the first administrator itself, before it opens the port:

```bash
--bootstrap-admin-enabled           # default: true
--bootstrap-admin-username=admin    # default username
STRUCTURED_LOG_BOOTSTRAP_ADMIN_PASSWORD or ..._FILE   # optional
```

Leave the password unset and one is generated and printed **once**, to
the startup log, marked temporary — this is what the Quick Start above
does. Set it yourself if you'd rather not rely on capturing a log line.
Either way this account is marked as *the* primary administrator — a
distinction that matters later (see
[Deleting an administrator](#deleting-an-administrator) below).

To re-create an administrator on a database that **already has users**
(the auto-bootstrap condition never fires there — e.g. every admin
account was accidentally blocked), use the explicit command instead:

```bash
dart run bin/server.dart create-admin \
  --db-path=/data/logs.db \
  --username=admin --password="$(openssl rand -base64 18)"
```

Unlike auto-bootstrap, a password set this way is **not** forced to
change at first login — you typed it yourself, so the situation is the
same as if the operator had chosen it directly. `create-admin` needs
only the database connection (no JWT secret, no other config) and
refuses to run at all if an active, non-deleted administrator already
exists.

## Managing the server day to day

### Managing users

Most day-to-day administration — creating users, granting roles,
managing groups/projects, reading the audit log — happens through the
admin client's UI as an `admin`-role account; see the
[User Guide](user-guide.md#if-youre-an-admin-users-and-the-audit-log)
for what that covers (creating accounts, resetting passwords, blocking/
deleting, the primary-administrator and sole-group-owner protections).
There is no separate operator-only user management path — the `admin`
role you'd sign in with yourself for this is the same one you grant to
anyone else who needs it. Everything the UI does goes through the same
HTTP API documented in [api/http-api.md](../api/http-api.md), so
scripting user/project provisioning against that API directly (bulk
onboarding, a CI pipeline creating a project per service) is equally
supported — see the
[Developer Guide](developer-guide.md#calling-the-management-api) for
that angle.

### Inspecting configuration

```bash
dart run bin/server.dart --print-config
```

prints every setting, its resolved value, and **where it came from**
(`cli`/`env`/`default`) — secrets shown as `***` plus their source, so
you can confirm a secret was picked up from where you expected without
ever seeing its value. Exits `0` without starting the server. `--help`
is generated from the same parameter table, so it can't drift from what
the parser actually accepts.

### Configuration surface

Every setting is a CLI flag, an environment variable
(`STRUCTURED_LOG_` + the flag name in `SCREAMING_SNAKE_CASE`), or a
built-in default, checked in that order of precedence — read once at
startup, never reloaded while the process runs (no config-reload
signal, no endpoint that edits settings; any change means a restart).
**Secrets never take a CLI flag at all** — only an environment variable
or a `_FILE` variant pointing at a mounted file, the same convention
Docker/Kubernetes secrets already use — because a process argument is
visible to every user on the host via `ps` and lands in shell history.

Full reference with every flag: [operations/configuration.md](../operations/configuration.md).
The ones you'll most likely actually touch:

| Concern | Settings |
|---|---|
| Network | `--http-host` (`0.0.0.0`), `--http-port` (`8080`) |
| Storage | `--db-backend`, `--db-path` or `--db-postgres-*` (above), `--db-read-pool-size` (SQLite only, `2`) |
| Signing secret | `STRUCTURED_LOG_JWT_SECRET`/`_FILE` — **required**, never auto-generated, at least 32 bytes |
| Ingestion limit | `--max-ingest-body-bytes` (`10485760`, 10 MiB) |
| Bootstrap | `--bootstrap-admin-enabled`/`-username`, `STRUCTURED_LOG_BOOTSTRAP_ADMIN_PASSWORD`/`_FILE` |
| Retention & purge | `--retention-purge-interval-seconds` (`3600`), `--audit-retention-days`/`--auth-event-retention-days` (unset = forever), `--audit-purge-batch-size` (`500`) |
| Own diagnostics | `--log-level` (`info`), `--log-format` (`console`/`json`), `--log-file`, `--log-max-file-bytes`/`-files` |
| Rate limiting | `--rate-limit-enabled` (`true`), `--rate-limit-bucket-capacity`/`-refill-per-minute` (`10`/`10`), `--rate-limit-max-keys` (`10000`) |
| Reverse proxy | `--trusted-proxy-hops` (`0`) |
| Live stream | `--sse-heartbeat-interval-seconds` (`25`) |
| Cross-origin access | `--cors-allowed-origins` (unset = off) |

**Nothing starts until everything checks out.** Configuration is parsed
and validated *before* the port opens or the database is touched — every
problem is reported in one pass, and the process exits with code
**`78`** (`EX_CONFIG`), distinct from a runtime crash, so a process
supervisor or container restart policy can tell "fix the configuration"
from "try again." An unknown flag stops the launch (almost certainly a
typo); an unknown `STRUCTURED_LOG_*` environment variable only warns —
a container's environment isn't exclusively yours, so a stranger's
variable shouldn't take the service down, but it isn't silently ignored
either.

## Behind a reverse proxy

Set `--trusted-proxy-hops` to the number of proxies genuinely in front
of the server (the bundled Compose setup, one nginx, uses `1`). The
server counts that many hops from the *right* of `X-Forwarded-For` to
find the real caller address, which the rate limiter buckets by. Get this wrong in either direction and you get a real problem:

- **Too low:** every client behind the proxy shares one rate-limit
  bucket — one busy user throttles everyone.
- **Too high:** a client can spoof its own address in a header the
  server now trusts, bypassing the limiter entirely.

## Cross-origin access (CORS)

Off by default (see [above](#what-youre-running)). Turn it on only when
the admin client (or your own client) is genuinely served from a
different origin than the API:

```bash
--cors-allowed-origins=https://admin.example.com,http://localhost:3000
```

Comma-separated, exact origins (scheme + host + port), case-sensitive,
no wildcard. An `Origin` not on the list gets no CORS headers at all —
not an error response, just silence, which is what a same-origin
request already looks like.

## Retention, quotas, and the audit log

Two independent retention mechanisms, easy to conflate:

- **Per-project log retention** (`retention_days`, required on every
  project — no project can opt out) deletes that project's log entries
  older than the window, via a periodic background purge
  (`--retention-purge-interval-seconds`). This is eventual, not
  real-time: under heavy load the purge can lag briefly behind the
  nominal window — an accepted trade-off, not a bug. A project can also
  cap itself by entry count and/or total bytes (`max_entries`/
  `max_bytes`, both optional, set via the UI or `PATCH /v1/projects/:id`)
  — once either limit is hit, further ingestion for that project is
  rejected per-entry (not the whole batch) until the purge job or a
  quota increase frees room.
- **Administrative audit log retention** (`--audit-retention-days` for
  administrative actions, `--auth-event-retention-days` for sign-in
  attempts — separate settings, both **unset by default**, meaning kept
  forever) governs the audit trail itself, not application log data.
  Upgrading the server never silently starts deleting history because
  of this — an explicit opt-in is required. There is no manual delete
  for an audit entry, by anyone, through any endpoint — only these two
  configured policies remove anything, and every purge pass that
  removed something leaves its own audit entry behind (`audit.purged`),
  so "why is last year's history gone" always has an answer inside the
  log itself.

## Backups

**SQLite.** The database is a single file at `--db-path`. With the
server stopped, a plain file copy is safe. With it running, prefer
`sqlite3 /data/logs.db ".backup '/backup/logs-$(date +%F).db'"` (the
SQLite online backup API) over copying the file directly — WAL mode
means the file alone, mid-write, isn't guaranteed self-consistent the
way a plain copy assumes. Inside the bundled Compose deployment, the
database lives on the named `data` volume:

```bash
docker run --rm -v structured-log_data:/data -v "$PWD":/backup alpine \
  tar czf /backup/data.tgz -C /data .
```

**PostgreSQL.** Ordinary `pg_dump`/`pg_basebackup`/your existing backup
tooling — this is exactly the operational story an operator choosing
this backend is usually already covering for their other services.

**Secrets.** `deploy/secrets/jwt_secret` (and, if you're running
PostgreSQL via the override above, `deploy/secrets/postgres_password`)
are not backed up by the steps above and are not meant to be reused
across a rebuild casually: replacing the JWT secret invalidates every
access token already issued, signing every user out at once — treat
losing and regenerating it as a deliberate, disruptive action, not a
routine one.

## Monitoring and health

```bash
curl http://localhost:8080/healthz
# {"status": "ok"}
```

No authentication, answers as long as the HTTP stack itself is serving
— point a load balancer's or orchestrator's health check at it
directly. If the process is down entirely, the endpoint doesn't answer
an error status; the connection is simply refused or times out, which
is itself the signal.

The server's own diagnostics (`--log-level`/`--log-format`/`--log-file`)
are separate from the log data it stores for tenants — set
`--log-format=json` for a container deployment so a log collector
parses it as structured data rather than a human-oriented console
stream (the bundled Compose deployment already does this). Passwords,
tokens, secret keys, and request bodies never appear in this output,
by design, not by redaction after the fact.

## Security checklist

- **The JWT signing secret is mandatory and is never generated for
  you.** A server that invented one at startup would silently
  invalidate every token on each restart — you'd see unexplained
  logouts in production instead of a clear refusal at boot. Set it
  once, keep it stable, and treat rotating it as equivalent to
  signing everyone out.
- **Every secret goes through the environment or a mounted file, never
  a flag.** If you find yourself tempted to pass one as a CLI argument,
  that flag genuinely doesn't exist — it's a deliberate omission, not a
  gap to work around.
- **TLS is your reverse proxy's job for the server's own listener**;
  the server itself speaks plain HTTP (terminate TLS at nginx/your load
  balancer, same as most services in this shape). For a PostgreSQL
  backend on a real network hop, keep `--db-postgres-ssl-mode` at its
  `require` default or above — `disable` is for same-host/local
  development only.
- **Rate limiting covers the auth endpoints specifically** — login
  attempts, password changes — not general API traffic, and there's no
  account lockout behind it (a design choice: usernames aren't secret
  in this system, so lockout would hand an attacker a way to freeze
  someone else's account on purpose). If you're already fronting the
  deployment with your own gateway's rate limiting, `--rate-limit-enabled=false`
  avoids doubling up.
- **`--trusted-proxy-hops` set wrong is a real vulnerability**, not just
  an inconvenience — see [above](#behind-a-reverse-proxy).
- **Bootstrap the first administrator deliberately.** Either capture
  the generated temporary password immediately, or set
  `STRUCTURED_LOG_BOOTSTRAP_ADMIN_PASSWORD_FILE` yourself before first
  start — don't leave the account sitting with an unknown password you
  never captured.

### Deleting an administrator

The very first administrator ever created on a given database (the
*primary* administrator — an identity, not a count: it's specifically
that one account, not "whichever admin happens to be last") can never
be deleted, by itself or by any other admin, no matter how many other
administrators exist. It can still be **blocked**, which is a gap worth
knowing about operationally: blocking the primary administrator with no
other active admin left effectively locks everyone out even though no
account was deleted. Keep more than one active administrator if this
matters to your deployment.

Deleting any account that is the **sole owner** of a group is refused
outright (`409 sole_group_owner`) until ownership is transferred to
someone else — the server won't let a deletion leave a group with no
owner at all, and won't guess who should get it.

## Upgrading

Stop the old process, deploy the new binary/image, start it. There is
no separate migration step to run by hand: the schema version is
checked and, if the database was written by an older schema, upgraded
in place automatically on the next start — this is the same mechanism
regardless of storage backend. Starting a **newer** binary against a
database written by a version *ahead* of what it understands refuses to
start outright, naming both versions in the error, rather than reading
tables it doesn't recognize — if you see that, you've rolled back a
binary past a database that already moved forward; restore a backup
taken before the newer version ran, or roll forward again.

Configuration is never migrated automatically between versions beyond
what the parameter table itself defines — a setting removed in a newer
version simply stops being read; one added arrives at its documented
default until you set it explicitly.

## Stopping the server safely

`SIGTERM`/`SIGINT` trigger a graceful shutdown: the retention purge
job and the live-stream broadcast stop first, in-flight requests are
allowed to finish, and the database connection (or connection pool,
under PostgreSQL) closes last. `docker compose down`/`docker stop` send
exactly this signal, so the default path is already safe — nothing to
do differently. A hard kill (`SIGKILL`, or pulling power) is the one
case that can leave an in-flight write incomplete; SQLite's WAL mode
and PostgreSQL's own durability both keep the database itself
consistent even then — you'd only lose whatever hadn't committed yet,
never end up with a corrupted file.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| Process exits immediately with code `78` | A configuration problem — re-run with `--print-config` (if it gets that far) or read the startup error, which names every problem found, not just the first |
| "STRUCTURED_LOG_JWT_SECRET is required" | The signing secret genuinely isn't set anywhere the resolver looked — check the exact env var name and that a `_FILE` path, if used, actually exists and is readable |
| "The signing secret must be at least 32 bytes in UTF-8" | The secret is set but too short to key HMAC-SHA256 properly. Replace it with `openssl rand -base64 48`; note that changing it invalidates every token already issued, so everyone signs in again |
| `create-admin` refuses: "An active administrator already exists" | Working as intended — this command only fires on a database with no active admin at all; block/reassign the existing one, or delete it (subject to the primary-administrator protection above) |
| Postgres backend: "connection refused" / timeout at startup | The server checks connectivity as part of startup validation and exits `78` rather than crashing on the first request — verify host/port/network reachability from *inside* the container if you're using Compose |
| Admin client shows "Server unreachable" | Usually a CORS or same-origin problem if the client is served from a different host than the API — see [above](#what-youre-running) — or the server process is genuinely down; check `/healthz` directly |
| Everyone suddenly signed out | The JWT secret changed (a restart with a different value/file), or every session's `token_version` was bumped by something (a password change cascades this only to that one account, so a mass sign-out points at the secret specifically) |
| An upload/ingest batch is rejected outright with `413` | The batch exceeds `--max-ingest-body-bytes` — raise the limit, or have the sending application split into smaller batches (`structured_log_http`, the reference client, already batches by size — see the [Developer Guide](developer-guide.md)) |

For anything not covered here, `--print-config` plus the server's own
diagnostic log (`--log-level=debug` temporarily) is the fastest way to
narrow down whether a problem is configuration, network, or something
worth filing an issue about.
