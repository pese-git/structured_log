# Configuration

*Читать на [русском](configuration.ru.md).*

Everything `structured_log_server` reads at startup, where it reads it
from, and what happens when it doesn't like what it finds. Design
rationale is decision 47 in
[design.md](../../openspec/changes/add-structured-log-server/design.md);
the behavioural contract is
[specs/log-server-config](../../openspec/changes/add-structured-log-server/specs/log-server-config/spec.md).

## Three sources, one order

**Command-line argument → environment variable → default.** A flag
always beats a variable, a variable always beats the built-in default.
Configuration is read once at startup and never changes while the
process runs — there is no SIGHUP reload and no endpoint that edits
settings; changing anything means restarting.

Names are derived mechanically, so the table below has one row per
setting rather than two:

```
--http-port  ↔  STRUCTURED_LOG_HTTP_PORT
--db-path    ↔  STRUCTURED_LOG_DB_PATH
```

kebab-case in the flag, the same words in SCREAMING_SNAKE with the
`STRUCTURED_LOG_` prefix in the environment. An empty environment
variable counts as *unset* (a `docker-compose` file makes empty values
too easy to produce for them to mean anything else).

## Secrets never travel as arguments

There is no `--jwt-secret` flag. Secrets are accepted **only** from the
environment, or from a file whose path is given in a `_FILE` variable —
the convention Docker and Kubernetes already use for mounted secrets:

```bash
STRUCTURED_LOG_JWT_SECRET=...            # direct
STRUCTURED_LOG_JWT_SECRET_FILE=/run/secrets/jwt   # from a mounted file
```

The same convention would apply to an SMTP password if email-sending
were implemented (it isn't yet — see the Reference table below); it
already applies to `STRUCTURED_LOG_DB_POSTGRES_PASSWORD` and to
`STRUCTURED_LOG_BOOTSTRAP_ADMIN_PASSWORD` — the first admin's password on
an empty database.

Process arguments are visible in `ps` to every user on the machine, land
in shell history, and get logged by supervisors — so the flag doesn't
exist rather than existing with a warning attached. Setting both forms
of the same secret is a **configuration error**, not a silent
precedence: in practice that combination means a half-finished migration
from one delivery method to the other, and quietly picking a winner
hides it until tokens start behaving strangely. A file's trailing
newline is stripped, so `echo secret > file` stores what you typed.

**The JWT signing secret is required and is never auto-generated.** A
server that invents a secret at startup silently invalidates every
issued token on each restart; an operator sees unexplained logouts in
production instead of a clear refusal at boot.

## Nothing starts until everything checks out

The configuration is parsed and validated **before** the port is opened
and before the database file is created. All problems are reported at
once — three bad values take one run to discover, not three — and the
process exits with **`78`** (`EX_CONFIG` from `sysexits.h`), distinct
from a runtime failure, so systemd, a Docker restart policy, or
Kubernetes can tell "restarting won't help" from "it crashed, try
again".

Two deliberate asymmetries:

- **An unknown flag stops the launch** — `--htp-port` is a typo, and
  that's what a CLI is expected to catch.
- **An unknown `STRUCTURED_LOG_*` variable only warns** — a container's
  environment isn't ours alone, so a stranger's variable must not take
  the service down. But it isn't silent either: `STRUCTURED_LOG_PROT=9000`
  would otherwise cost an operator an hour of "why is it ignoring my
  port".

Values are parsed strictly: booleans accept `true/false/1/0/yes/no`
(any case) and nothing else — `…=off` is an error, not a quiet `false`
that would disable a protection you believed was on. Durations and
sizes are plain integers with the unit **in the name**
(`--access-token-ttl-seconds`, `--audit-retention-days`,
`--max-batch-bytes`) rather than strings like `30m`/`10MB`, which are a
small language of their own with their own ambiguities.

## Inspecting what the server actually took

```bash
dart run bin/server.dart --print-config
```

prints every setting with its resolved value **and its source**
(`cli` / `env` / `default`), then exits `0` without starting anything.
Secrets are shown as `***` plus their source — enough to confirm the
secret was picked up from where you expected, and nothing more. This is
the direct answer to the most common operational question: *why is it
running with settings I didn't set?*

`--help` is generated from the same parameter declarations the parser
uses, so it cannot drift from the real set of options.

## Which settings a command needs

Not every setting applies to every subcommand. For example,
`create-admin` ([auth.md](../architecture/auth.md)) only needs a
database path — it shouldn't be blocked on a JWT secret it never uses.
Bootstrap-admin settings (`--bootstrap-admin-username`,
`STRUCTURED_LOG_BOOTSTRAP_ADMIN_PASSWORD`) are read only by a normal
server start, and none of them is required: an unset password just
means one gets generated.

## Reference

Most rows below show a concrete default (or `—` where the setting is
required and has none). This table also carries a few rows for
capabilities that are part of the original design (self-registration,
password reset, email verification — see
[auth.md](../architecture/auth.md)) but have **no corresponding flag
in the running server at all**; each is marked "planned, not
implemented" in its Notes column, so a value listed there is what the
flag *would* be named if the capability existed, not a flag you can
pass today.

| Setting | Flag / variable | Default | Notes |
|---|---|---|---|
| HTTP host | `--http-host` | `0.0.0.0` | |
| HTTP port | `--http-port` | `8080` | |
| Storage backend | `--db-backend` | `sqlite` | `sqlite` or `postgres`, operator's choice at deploy time — never switched at runtime ([add-postgres-backend](../../openspec/changes/add-postgres-backend/design.md)) |
| Database file | `--db-path` | — | Required for every command, `create-admin` included, only when `--db-backend=sqlite` (the default) |
| PostgreSQL host | `--db-postgres-host` | — | Required for every command when `--db-backend=postgres` |
| PostgreSQL port | `--db-postgres-port` | `5432` | |
| PostgreSQL database | `--db-postgres-database` | — | Required when `--db-backend=postgres` |
| PostgreSQL username | `--db-postgres-username` | — | Required when `--db-backend=postgres` |
| PostgreSQL password | `STRUCTURED_LOG_DB_POSTGRES_PASSWORD` / `…_FILE` | — | Secret: no flag. Required when `--db-backend=postgres` |
| PostgreSQL connection pool size | `--db-postgres-pool-size` | `10` | `1`–`64`; shared by reads and writes alike — unlike `--db-read-pool-size`, which is SQLite-only and has no effect here |
| PostgreSQL TLS mode | `--db-postgres-ssl-mode` | `require` | `disable` / `require` (encrypted, certificate errors ignored) / `verify-full` (encrypted and certificate-verified) |
| JWT signing secret | `STRUCTURED_LOG_JWT_SECRET` / `…_FILE` | — | **Required**, no flag, never generated; at least 32 bytes or the server refuses to start |
| JWT issuer | `--jwt-issuer` | `structured_log_server` | The `iss` claim embedded in access tokens |
| Access token lifetime | *(no flag)* | `900` (15 min) | **Planned, not implemented as a setting** — currently a fixed constant in code, not configurable |
| Refresh token lifetime | *(no flag)* | `2592000` (30 days) | **Planned, not implemented as a setting** — currently a fixed constant in code, not configurable |
| Self-registration | *(no flag)* | — | **Planned, not implemented** — no `POST /v1/auth/register` route exists ([auth.md](../architecture/auth.md)) |
| SMTP host / port | *(no flag)* | — | **Planned, not implemented** — no email-sending capability exists in the running server |
| SMTP username | *(no flag)* | — | **Planned, not implemented** |
| SMTP password | *(no flag)* | — | **Planned, not implemented** |
| Sender address | *(no flag)* | — | **Planned, not implemented** |
| Password-reset link base | *(no flag)* | — | **Planned, not implemented** — no `POST /v1/auth/password-reset` route exists; an admin resets a password via `PATCH /v1/users/:id` instead |
| Password-reset token lifetime | *(no flag)* | — | **Planned, not implemented** |
| Email-verification link base | *(no flag)* | — | **Planned, not implemented** — no `POST /v1/auth/verify-email` route exists |
| Email-verification token lifetime | *(no flag)* | — | **Planned, not implemented** |
| Ingestion body limit | `--max-ingest-body-bytes` | `10485760` (10 MiB) | Exceeding it is `413`, whole batch ([errors.md](../api/errors.md)) |
| Retention sweep interval | `--retention-purge-interval-seconds` | `3600` | One timer for log retention and audit retention both |
| Rate limiting | `--rate-limit-enabled` / `--no-rate-limit-enabled` | `true` | Turn off behind your own gateway ([auth.md](../architecture/auth.md#rate-limiting-throttling-without-lockout)) |
| Bucket capacity / refill | `--rate-limit-bucket-capacity`, `--rate-limit-refill-per-minute` | `10` / `10` | One capacity, shared by the IP bucket (spent on every request) and the subject bucket (spent on failures only, refilled on success) — there is no separate per-kind setting |
| Limiter key ceiling | `--rate-limit-max-keys` | `10000` | LRU eviction above it |
| Trusted proxy hops | `--trusted-proxy-hops` | `0` | `0` = ignore `X-Forwarded-For` entirely |
| CORS allowed origins | `--cors-allowed-origins` | unset | Comma-separated exact origins; unset/empty = no CORS headers at all ([log-server-api](../../openspec/changes/add-server-cors/specs/log-server-api/spec.md)) |
| Audit retention | `--audit-retention-days` | unset | Unset = keep forever ([quotas-and-audit.md](../architecture/quotas-and-audit.md)) |
| Auth-event retention | `--auth-event-retention-days` | unset | Separate from the above on purpose |
| Audit purge chunk | `--audit-purge-batch-size` | `500` | Deleting in chunks keeps ingestion unblocked |
| Database read connections | `--db-read-pool-size` | `2` | Extra connections beside the single writer, `0`–`16`; `0` sends reads through the writer. Reads no longer queue behind ingestion. SQLite only — under `--db-backend=postgres` a non-default value only warns at startup, it has no effect (see "PostgreSQL" below) |
| Live-stream heartbeat | `--sse-heartbeat-interval-seconds` | `25` | Also re-validates authorization ([live-streaming.md](../architecture/live-streaming.md)) |
| Live subscriptions per account | `--max-live-subscriptions-per-user` | `10` | `0` for no limit. One past it is `429 too_many_subscriptions`. A client that vanishes without closing keeps its place until the server's next write to the socket — up to one `--sse-heartbeat-interval-seconds` |
| Live subscriptions in total | `--max-live-subscriptions` | `1000` | Across every account; `0` for no limit |
| Own-log level | `--log-level` | `info` | The server's own diagnostics, not ingested entries ([README.md](../architecture/README.md#the-middleware-chain)) |
| Own-log format | `--log-format` | `console` | `console` or `json` for machine collection |
| Own-log file | `--log-file` | unset | Unset = console. When set, writing is asynchronous with rotation so it never blocks the single isolate |
| Own-log rotation | `--log-max-file-bytes`, `--log-max-files` | `10485760` (10 MiB) / `5` | Only meaningful together with `--log-file` |
| Auto-bootstrap admin | `--bootstrap-admin-enabled` / `--no-bootstrap-admin-enabled` | `true` | Creates the first admin when the `users` table is empty ([rbac-and-lifecycle.md](../architecture/rbac-and-lifecycle.md#bootstrap-two-paths-to-the-first-admin)) |
| Bootstrap admin username | `--bootstrap-admin-username` | `admin` | Only used when the table is empty |
| Bootstrap admin password | `STRUCTURED_LOG_BOOTSTRAP_ADMIN_PASSWORD` / `…_FILE` | generated | Secret: no flag. Unset = a random one is generated and printed once, marked temporary. A value must be 8 characters to 72 bytes, like any password set through the API; anything else stops startup with a configuration error that names the variable, never the value |

## The database file

Fixed, not configurable — recorded here because they decide what a crash or a rollback costs. Applies only under the default `--db-backend=sqlite`; see "PostgreSQL" below for the other backend.

- **WAL mode, `synchronous=NORMAL`.** A committed write is safe if the *process* dies; if the *machine* loses power, the last few commits can be lost. The database is never left corrupt either way. `FULL` (SQLite's default) would fsync on every ingest batch.
- **`busy_timeout` of 5 seconds.** A second process on the same file — `create-admin` run while the server is up — waits out a write instead of failing at once.
- **Schema version.** Starting a build against a database written by a *newer* schema refuses with a message naming both versions, rather than reading tables it does not understand. After a bad deploy, roll forward or restore a backup taken before the upgrade. Older databases are upgraded in place on start.

## PostgreSQL

`--db-backend=postgres` swaps the storage engine for an operator-managed
PostgreSQL server — an opt-in alternative to the default SQLite file, not
a replacement for it. Nothing observable through the HTTP API changes
between the two; the choice is purely operational (design rationale:
[add-postgres-backend](../../openspec/changes/add-postgres-backend/design.md)).

- **Connection**, not a file path: `--db-postgres-host`/`-port`/`-database`/`-username`
  plus the `STRUCTURED_LOG_DB_POSTGRES_PASSWORD`/`…_FILE` secret (same
  mounted-file convention as the JWT secret). All four of host/database/username/password
  are required when this backend is selected — validated at startup, same
  as every other setting.
- **One pool, not two.** SQLite's read/write split (`--db-read-pool-size`)
  exists to work around a single file having one writer; PostgreSQL's
  MVCC doesn't have that constraint, so reads and writes share one pool
  sized by `--db-postgres-pool-size` (default `10`). `--db-read-pool-size`
  is ignored under this backend — set to a non-default value, it only
  warns at startup, the same way an unknown `STRUCTURED_LOG_*` variable
  does.
- **TLS is on by default.** `--db-postgres-ssl-mode` defaults to `require`
  (encrypted, but the server certificate isn't verified — the common case
  for a managed Postgres behind the provider's own network). Use
  `verify-full` when certificate verification matters, or `disable` for a
  local development instance with no TLS configured at all.
- **The `PRAGMA`-level tuning above (WAL, `busy_timeout`) doesn't apply**
  and has no PostgreSQL equivalent here — those exist to work around
  SQLite's single-writer file, not something PostgreSQL needs.
- **Startup fails fast, the same way a bad `--db-path` does.** An
  unreachable host or bad credentials are caught by a connection check
  before the port opens, exiting `78` — never a runtime crash on the
  first request.
- **Out of scope:** there is no built-in path to convert an existing
  SQLite database into PostgreSQL, or the reverse. The backend is chosen
  once, on an empty database, at first deploy.

## Examples

```bash
# First boot: a database path and a JWT secret are all it takes — the
# first admin is created automatically, with a generated temporary
# password printed once to the startup log
STRUCTURED_LOG_JWT_SECRET=$(openssl rand -hex 32) \
  dart run bin/server.dart --db-path /data/logs.db
```

```bash
# Development: everything from flags, secret from the environment
STRUCTURED_LOG_JWT_SECRET=dev-only-secret-long-enough-to-start \
  dart run bin/server.dart --db-path ./dev.db --http-port 8080
```

```bash
# Container: settings from the environment, secret from a mounted file
docker run \
  -e STRUCTURED_LOG_DB_PATH=/data/logs.db \
  -e STRUCTURED_LOG_HTTP_PORT=8080 \
  -e STRUCTURED_LOG_JWT_SECRET_FILE=/run/secrets/jwt \
  -e STRUCTURED_LOG_AUTH_EVENT_RETENTION_DAYS=90 \
  -e STRUCTURED_LOG_TRUSTED_PROXY_HOPS=1 \
  -v /srv/logs:/data -v /srv/secrets/jwt:/run/secrets/jwt:ro \
  structured-log-server
```

```bash
# One-off override: same environment, different port
dart run bin/server.dart --http-port 9090
```

```bash
# Against PostgreSQL instead of the default SQLite file
STRUCTURED_LOG_JWT_SECRET=$(openssl rand -hex 32) \
STRUCTURED_LOG_DB_POSTGRES_PASSWORD=... \
  dart run bin/server.dart \
  --db-backend postgres \
  --db-postgres-host db.internal --db-postgres-database structured_log \
  --db-postgres-username structured_log
```

```bash
# Re-bootstrap on a non-empty database (auto-creation never fires there);
# no JWT secret needed for this command
dart run bin/server.dart create-admin --db-path /data/logs.db \
  --username admin --password "$(read -rsp 'password: ' p; echo "$p")"
```

## See also

- [auth.md](../architecture/auth.md) — what the JWT secret and rate
  limiter actually govern (also covers the still-unimplemented
  registration/password-reset/email-verification design).
- [quotas-and-audit.md](../architecture/quotas-and-audit.md) — the two
  retention settings and what they delete.
- [http-api.md](../api/http-api.md) — the endpoints these settings shape.
