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

The same applies to `STRUCTURED_LOG_SMTP_PASSWORD` and to
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

Bootstrap settings are read only by a normal server start, never by
`create-admin`, and none of them is required: an unset password means
"generate one", not "fail". Requirements are evaluated per command. `create-admin`
([auth.md](../architecture/auth.md)) needs only the database path —
demanding a JWT secret and SMTP settings from a command that writes one
row would block first-time setup on mail configuration that isn't
relevant yet.

## Reference

Defaults marked *TBD* are deliberately not fixed by the design — they
are settled with the first implementation (see design.md's Open
Questions).

| Setting | Flag / variable | Default | Notes |
|---|---|---|---|
| HTTP host | `--http-host` | `0.0.0.0` | |
| HTTP port | `--http-port` | `8080` | |
| Database file | `--db-path` | — | Required for every command, `create-admin` included |
| JWT signing secret | `STRUCTURED_LOG_JWT_SECRET` / `…_FILE` | — | **Required**, no flag, never generated |
| Access token lifetime | `--access-token-ttl-seconds` | TBD | |
| Refresh token lifetime | `--refresh-token-ttl-seconds` | TBD | |
| Self-registration | `--registration-enabled` / `--no-registration-enabled` | `false` | Closed corporate deployments leave it off ([auth.md](../architecture/auth.md)) |
| SMTP host / port | `--smtp-host`, `--smtp-port` | — | Required only if email features are used |
| SMTP username | `--smtp-username` | — | |
| SMTP password | `STRUCTURED_LOG_SMTP_PASSWORD` / `…_FILE` | — | Secret: no flag |
| Sender address | `--smtp-from` | — | |
| Password-reset link base | `--password-reset-base-url` | — | Web build only; the token is always enterable by hand |
| Password-reset token lifetime | `--password-reset-ttl-seconds` | TBD | |
| Email-verification link base | `--email-verification-base-url` | — | |
| Email-verification token lifetime | `--email-verification-ttl-seconds` | TBD | Can be far longer than a reset token |
| Ingestion body limit | `--max-batch-bytes` | TBD | Exceeding it is `413`, whole batch ([errors.md](../api/errors.md)) |
| Retention sweep interval | `--purge-interval-seconds` | TBD | One timer for log retention and audit retention both |
| Rate limiting | `--rate-limit-enabled` / `--no-rate-limit-enabled` | `true` | Turn off behind your own gateway ([auth.md](../architecture/auth.md#rate-limiting-throttling-without-lockout)) |
| IP bucket capacity / refill | `--rate-limit-ip-capacity`, `--rate-limit-ip-refill-per-minute` | TBD | Spent on every request to a limited path |
| Subject bucket capacity / refill | `--rate-limit-subject-capacity`, `--rate-limit-subject-refill-per-minute` | TBD | Spent on failures only; a success refills it |
| Limiter key ceiling | `--rate-limit-max-keys` | TBD | LRU eviction above it |
| Trusted proxy hops | `--trusted-proxy-hops` | `0` | `0` = ignore `X-Forwarded-For` entirely |
| CORS allowed origins | `--cors-allowed-origins` | unset | Comma-separated exact origins; unset/empty = no CORS headers at all ([log-server-api](../../openspec/changes/add-server-cors/specs/log-server-api/spec.md)) |
| Audit retention | `--audit-retention-days` | unset | Unset = keep forever ([quotas-and-audit.md](../architecture/quotas-and-audit.md)) |
| Auth-event retention | `--auth-event-retention-days` | unset | Separate from the above on purpose |
| Audit purge chunk | `--audit-purge-batch-size` | `500` | Deleting in chunks keeps ingestion unblocked |
| Database read connections | `--db-read-pool-size` | `2` | Extra connections beside the single writer, `0`–`16`; `0` sends reads through the writer. Reads no longer queue behind ingestion |
| Live-stream heartbeat | `--stream-heartbeat-seconds` | TBD | Also re-validates authorization ([live-streaming.md](../architecture/live-streaming.md)) |
| Own-log level | `--log-level` | `info` | The server's own diagnostics, not ingested entries ([README.md](../architecture/README.md#the-middleware-chain)) |
| Own-log format | `--log-format` | `console` | `console` or `json` for machine collection |
| Own-log file | `--log-file` | unset | Unset = console. When set, writing is asynchronous with rotation so it never blocks the single isolate |
| Own-log rotation | `--log-file-max-bytes`, `--log-file-max-files` | TBD | Only meaningful together with `--log-file` |
| Auto-bootstrap admin | `--bootstrap-admin-enabled` / `--no-bootstrap-admin-enabled` | `true` | Creates the first admin when the `users` table is empty ([rbac-and-lifecycle.md](../architecture/rbac-and-lifecycle.md#bootstrap-two-paths-to-the-first-admin)) |
| Bootstrap admin username | `--bootstrap-admin-username` | `admin` | Only used when the table is empty |
| Bootstrap admin password | `STRUCTURED_LOG_BOOTSTRAP_ADMIN_PASSWORD` / `…_FILE` | generated | Secret: no flag. Unset = a random one is generated and printed once, marked temporary. A value must be 8 characters to 72 bytes, like any password set through the API; anything else stops startup with a configuration error that names the variable, never the value |

## The database file

Fixed, not configurable — recorded here because they decide what a crash or a rollback costs:

- **WAL mode, `synchronous=NORMAL`.** A committed write is safe if the *process* dies; if the *machine* loses power, the last few commits can be lost. The database is never left corrupt either way. `FULL` (SQLite's default) would fsync on every ingest batch.
- **`busy_timeout` of 5 seconds.** A second process on the same file — `create-admin` run while the server is up — waits out a write instead of failing at once.
- **Schema version.** Starting a build against a database written by a *newer* schema refuses with a message naming both versions, rather than reading tables it does not understand. After a bad deploy, roll forward or restore a backup taken before the upgrade. Older databases are upgraded in place on start.

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
STRUCTURED_LOG_JWT_SECRET=dev-only-secret \
  dart run bin/server.dart --db-path ./dev.db --http-port 8080 --registration-enabled
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
# Re-bootstrap on a non-empty database (auto-creation never fires there);
# no JWT secret or SMTP needed for this command
dart run bin/server.dart create-admin --db-path /data/logs.db \
  --username admin --password "$(read -rsp 'password: ' p; echo "$p")"
```

## See also

- [auth.md](../architecture/auth.md) — what the JWT secret, registration
  switch and rate limiter actually govern.
- [quotas-and-audit.md](../architecture/quotas-and-audit.md) — the two
  retention settings and what they delete.
- [http-api.md](../api/http-api.md) — the endpoints these settings shape.
