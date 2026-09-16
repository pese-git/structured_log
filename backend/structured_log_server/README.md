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
> groups, projects, secret keys, authentication and RBAC work today. User
> management, teams, role assignment, the audit log, password recovery and
> email verification are specified but not implemented — see
> [tasks.md](../../openspec/changes/add-structured-log-server/tasks.md) for
> exactly what is and isn't there.

## What it does

- **Ingest** — `POST /v1/logs`, authenticated by a per-project secret key
- **Query** — `GET /v1/logs` with filters, paging, and full-text search
- **Live stream** — `GET /v1/logs/stream`, Server-Sent Events with catch-up
- **Multi-tenancy** — groups own projects; roles are granted per scope
- **Quotas** — per-project entry/byte limits and a retention window
- **Rate limiting** — token buckets on the auth endpoints, by address and by subject
- **SQLite storage** — one file, no external services

## Requirements

Dart SDK 3.0 or newer. Nothing else: the database is an embedded SQLite file
and there is no message broker, cache or migration tool to run.

## Running it

```bash
cd backend/structured_log_server
dart pub get
dart run build_runner build --delete-conflicting-outputs   # drift/freezed/router code

export STRUCTURED_LOG_JWT_SECRET='a-long-random-string'
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

| Setting | Default |
|---|---|
| `--db-path` | required for `serve` |
| `STRUCTURED_LOG_JWT_SECRET` | required for `serve` |
| `--http-host` / `--http-port` | `0.0.0.0` / `8080` |
| `--max-ingest-body-bytes` | `10485760` |
| `--retention-purge-interval-seconds` | `3600` |
| `--log-level` / `--log-format` / `--log-file` | `info` / `console` / console |
| `--rate-limit-*` | enabled, 10 tokens, 10/min, 10000 keys |
| `--trusted-proxy-hops` | `0` — `X-Forwarded-For` ignored |
| `--sse-heartbeat-interval-seconds` | `25` |
| `--audit-retention-days` | unset — audit records are kept indefinitely |
| `--auth-event-retention-days` | unset — `auth.*` records are kept indefinitely |
| `--audit-purge-batch-size` | `500` |

Full list with descriptions:
[docs/operations/configuration.md](../../docs/operations/configuration.md).

**Behind a reverse proxy**, set `--trusted-proxy-hops` to the number of
proxies in front. Left at `0` the rate limiter keys on the socket address,
which behind a proxy is the proxy — every client would share one bucket.

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
dart test                          # unit and integration
dart test --tags integration       # just the ones that spawn a real process
```

Code generation is not optional — `drift`, `freezed`, `json_serializable`
and `shelf_router_generator` all produce code the package does not compile
without, and none of it is committed.

## License

MIT — see [LICENSE](LICENSE).
