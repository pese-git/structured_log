# structured_log_server

[![CI](https://github.com/pese-git/structured_log/actions/workflows/ci.yml/badge.svg)](https://github.com/pese-git/structured_log/actions/workflows/ci.yml)

*Читать на [русском](README.ru.md).*

Self-hosted log server for
[`structured_log`](https://pub.dev/packages/structured_log): applications
ship entries to it over HTTP, people read them back through a query API and
a live stream.

Not published to pub.dev — this is a service you run, not a library you
depend on.

> **Status: in development.** Log ingestion, querying, the live stream,
> groups, projects, secret keys, authentication, RBAC, the audit log, user
> lifecycle management (create/block/delete), teams, and role assignment
> (including an `owner` granting roles within their own group) work today.
> Self-registration, password recovery and email verification are
> specified but not implemented — see
> [tasks.md](../../openspec/changes/add-structured-log-server/tasks.md) for
> exactly what is and isn't there.

## What it does

- **Ingest** — `POST /v1/logs`, authenticated by a per-project secret key
- **Query** — `GET /v1/logs` with filters, paging, and full-text search
- **Live stream** — `GET /v1/logs/stream`, Server-Sent Events with catch-up
- **Multi-tenancy** — groups own projects and teams; roles are granted per
  scope, to a user or to a whole team at once
- **User management** — `admin` creates/edits/blocks/deletes accounts
  (`POST`/`GET`/`PATCH`/`DELETE /v1/users`)
- **Teams** — `owner`/`admin` create a group's teams and manage membership
  (`POST /v1/groups/:groupId/teams`,
  `POST`/`DELETE /v1/teams/:teamId/members`)
- **Role assignments** — `admin` grants any role anywhere; a group's
  `owner` grants `owner`/`user` within that group and its projects
  (`POST`/`DELETE /v1/role-assignments`)
- **Quotas** — per-project entry/byte limits and a retention window
- **Rate limiting** — token buckets on the auth endpoints, by address and by subject
- **Audit log** — `GET /v1/audit-log`, administrators only: who changed what,
  and who tried to sign in
- **Storage** — SQLite by default (one file, no external services), or
  PostgreSQL as an operator-chosen alternative (`--db-backend=postgres`)

## Requirements

Dart SDK 3.0 or newer. Nothing else by default: the database is an embedded
SQLite file and there is no message broker, cache or migration tool to run.
Choosing `--db-backend=postgres` instead needs a PostgreSQL server the
operator already runs — see
[Running against PostgreSQL instead](#running-against-postgresql-instead)
below.

## Running it

```bash
cd backend/structured_log_server
dart pub get
dart run build_runner build --delete-conflicting-outputs   # drift/freezed/router code

export STRUCTURED_LOG_JWT_SECRET="$(openssl rand -base64 48 | tr -d '\n')"
dart run bin/server.dart serve --db-path=./logs.sqlite
```

The signing secret has no CLI flag on purpose — secrets come from the
environment, where they don't end up in shell history or a process listing.

`dart run bin/server.dart --print-config` prints every effective setting and
where it came from, with secrets masked. `--help` lists the flags.

### The first administrator

On an empty database the server creates one for you and logs a temporary
password at `warning` level, once, at creation:

```
Generated a temporary password for bootstrap administrator "admin": <...>
— it must be changed at first login.
```

That is the only channel this password has, so capture it. Set
`STRUCTURED_LOG_BOOTSTRAP_ADMIN_PASSWORD` to choose it yourself, in which
case nothing is printed; set `--no-bootstrap-admin-enabled` to skip
auto-creation and use `dart run bin/server.dart create-admin` instead.

Either way the account starts with `must_change_password`, and every
endpoint except the change-password one answers `403 must_change_password`
until it is cleared.

### Running against PostgreSQL instead

Everything above works identically against PostgreSQL — swap `--db-path`
for `--db-backend=postgres` plus connection settings, nothing else in this
README changes:

```bash
export STRUCTURED_LOG_JWT_SECRET="$(openssl rand -base64 48 | tr -d '\n')"
export STRUCTURED_LOG_DB_POSTGRES_PASSWORD='...'
dart run bin/server.dart serve \
  --db-backend=postgres \
  --db-postgres-host=localhost --db-postgres-database=structured_log \
  --db-postgres-username=structured_log
```

The backend is chosen once, on an empty database, at deploy time — never a
runtime toggle and never an automatic SQLite→PostgreSQL migration. See
[docs/operations/configuration.md](../../docs/operations/configuration.md#postgresql)
for every Postgres-specific setting (pool size, TLS mode) and
[docs/architecture/data-model.md](../../docs/architecture/data-model.md#postgresql-an-operator-chosen-alternative-backend)
for what genuinely differs between the two backends.

## Getting to your first log entry

```bash
BASE=http://localhost:8080

# 1. Log in. Form-encoded, RFC 6749 shaped.
TOKEN=$(curl -s -X POST $BASE/v1/auth/token \
  -d 'grant_type=password&username=admin&password=<temporary>' \
  | jq -r .access_token)

# 2. Clear the temporary password.
curl -s -X POST $BASE/v1/auth/change-password \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"current_password": "<temporary>", "new_password": "<new>"}'
TOKEN=$(curl -s -X POST $BASE/v1/auth/token \
  -d 'grant_type=password&username=admin&password=<new>' | jq -r .access_token)

# 3. A group owns projects.
GROUP=$(curl -s -X POST $BASE/v1/groups \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"name": "payments"}' | jq -r .id)

# 4. A project carries the quota. retention_days is required.
PROJECT=$(curl -s -X POST $BASE/v1/groups/$GROUP/projects \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"name": "checkout", "retention_days": 30, "max_entries": 1000000}' \
  | jq -r .id)

# 5. A secret key authenticates ingestion. Shown exactly once.
KEY=$(curl -s -X POST $BASE/v1/projects/$PROJECT/secret-keys \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"label": "prod"}' | jq -r .secret)

# 6. Ship an entry with the key...
curl -s -X POST $BASE/v1/logs \
  -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' \
  -d '[{"event": "checkout_started", "level": "info",
        "timestamp": "'"$(date -u +%FT%TZ)"'", "order_id": 42}]'

# 7. ...and read it back with the access token.
curl -s "$BASE/v1/logs?project_id=$PROJECT" -H "Authorization: Bearer $TOKEN"
```

From an application, use
[`structured_log_http`](../../emb/structured_log_http) rather than `curl`:
it batches, retries and never blocks the code that logged.

## Reading the audit log

Every administrative act and every authentication attempt is recorded, and
`GET /v1/audit-log` is the only way to read them back. It is global-admin
only: the journal spans every tenant, so there is no filtered view of it that
would be safe to offer an owner, and there is none.

```bash
curl -s -H "Authorization: Bearer $ADMIN_TOKEN" \
  'http://localhost:8080/v1/audit-log?action=auth.login_failed&limit=50'
```

Filters (`actor_user_id`, `action`, `target_type`, `target_id`, `from`, `to`)
combine, and paging is by `cursor` — pass back the `next_cursor` of the
previous page. An `action` outside the published set is refused with 400
rather than answered with an empty page: in a journal whose job is answering
"did this happen", a typo that reads as "nothing happened" is the one wrong
answer that matters.

Two things the journal never contains: the value of a secret key, and the
username submitted in a failed login under an account that does not exist —
that attempt is recorded as `unknown_user` with no actor, because the string
is regularly a password typed into the wrong box and the journal outlives the
mistake.

Nothing deletes from it but retention. There is no endpoint that edits or
removes a record, and a test refuses to let one appear.

## Two credentials, one header

Both arrive as `Authorization: Bearer <...>`, and the server tells them
apart by shape:

| | Ingestion | Everything else |
|---|---|---|
| Credential | Project secret key, prefixed `slk_` | Access token (JWT) |
| Held by | An application | A person |
| Identifies | A project | A user, with roles |

Presenting one where the other belongs answers `401`, exactly as a missing
credential does.

## Watching logs arrive

```bash
curl -N "$BASE/v1/logs/stream?project_id=$PROJECT&level=warning" \
  -H "Authorization: Bearer $TOKEN"
```

Server-Sent Events, filtered by the same parameters as `GET /v1/logs`. Pass
`since_id=<last id you saw>` when reconnecting and the stream replays what
was missed before continuing live — without duplicates. A keep-alive
comment arrives every `--sse-heartbeat-interval-seconds`, and the same tick
re-checks that the caller may still hold the connection.

## Configuration

Every setting is a CLI flag, an environment variable
(`STRUCTURED_LOG_` + the flag in upper snake case), or a default — in that
order of priority. Secrets are environment-only.

<!-- config-reference:implemented -->

| Setting | Default |
|---|---|
| `--db-backend` | `sqlite` — or `postgres`, see above |
| `--db-path` | required for `serve` when `--db-backend=sqlite` (the default) |
| `--db-postgres-host` / `-database` / `-username`, `STRUCTURED_LOG_DB_POSTGRES_PASSWORD` | required for `serve` when `--db-backend=postgres` |
| `STRUCTURED_LOG_JWT_SECRET` | required for `serve`; at least 32 bytes |
| `--http-host` / `--http-port` | `0.0.0.0` / `8080` |
| `--max-ingest-body-bytes` | `10485760` |
| `--retention-purge-interval-seconds` | `3600` |
| `--log-level` / `--log-format` / `--log-file` | `info` / `console` / console |
| `--rate-limit-*` | enabled, 10 tokens, 10/min, 10000 keys |
| `--trusted-proxy-hops` | `0` — `X-Forwarded-For` ignored |
| `--sse-heartbeat-interval-seconds` | `25` |
| `--max-live-subscriptions-per-user` | `10` (`0` = no limit) |
| `--max-live-subscriptions` | `1000` (`0` = no limit) |
| `--cors-allowed-origins` | unset — no CORS headers on any response |
| `--audit-retention-days` | unset — audit records are kept indefinitely |
| `--auth-event-retention-days` | unset — `auth.*` records are kept indefinitely |
| `--audit-purge-batch-size` | `500` |
| `--db-read-pool-size` | `2` |

<!-- /config-reference -->

Full list with descriptions:
[docs/operations/configuration.md](../../docs/operations/configuration.md).

**Behind a reverse proxy**, set `--trusted-proxy-hops` to the number of
proxies in front. Left at `0` the rate limiter keys on the socket address,
which behind a proxy is the proxy — every client would share one bucket.

**CORS is off by default** — the bundled deployment ([deploy/](../../deploy))
serves the admin client and the API behind one origin, which needs none.
Set `--cors-allowed-origins` (comma-separated) only when the client is
genuinely served from elsewhere, such as a client run against this server
on its own port during local development; an origin not in the list gets no
headers regardless.

## Documentation

- [docs/api/http-api.md](../../docs/api/http-api.md) — every endpoint, wire shapes
- [docs/api/models.md](../../docs/api/models.md) — JSON models
- [docs/api/errors.md](../../docs/api/errors.md) — error codes
- [docs/architecture/](../../docs/architecture/) — auth, RBAC, storage, live streaming, quotas
- [openspec/changes/add-structured-log-server/](../../openspec/changes/add-structured-log-server/) — requirements and design decisions

## Development

```bash
dart run build_runner build --delete-conflicting-outputs
dart analyze
dart test --exclude-tags integration --exclude-tags postgres   # the default suite
dart test --tags integration                # spawns a real process
dart test --tags postgres --concurrency=1   # needs a real PostgreSQL instance
```

Code generation is not optional — `drift`, `freezed`, `json_serializable`
and `shelf_router_generator` all produce code the package does not compile
without, and none of it is committed.

## License

MIT — see [LICENSE](LICENSE).
