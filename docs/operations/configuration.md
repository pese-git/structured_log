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

The same applies to `STRUCTURED_LOG_BOOTSTRAP_ADMIN_PASSWORD` — the
first admin's password on an empty database — and to every secret added
later, the SMTP password included.

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
(`--retention-purge-interval-seconds`, `--sse-heartbeat-interval-seconds`,
`--max-ingest-body-bytes`) rather than strings like `30m`/`10MB`, which
are a small language of their own with their own ambiguities.

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
uses, so it cannot drift from the real set of options. When this page
and `--help` disagree, `--help` is right — and the mismatch is a bug in
this page, which
[`test/config/configuration_docs_test.dart`](../../backend/structured_log_server/test/config/configuration_docs_test.dart)
exists to catch.

## Which settings a command needs

Bootstrap settings are read only by a normal server start and by
`create-admin`, and none of them is required: an unset password means
"generate one", not "fail". Requirements are evaluated per command.
`create-admin` ([auth.md](../architecture/auth.md)) needs only the
database path — demanding a JWT secret from a command that writes one
row would block first-time setup on settings that aren't relevant yet,
and the same will hold for the mail settings when they arrive.

## Reference

Every flag below is declared in
[`serverConfigParams`](../../backend/structured_log_server/lib/src/config/server_config.dart),
which is what the parser, the env var names and `--help` are all built
from. Sizes are bytes and intervals are seconds, as their names say.

<!-- config-reference:implemented -->

| Setting | Flag / variable | Default | Notes |
|---|---|---|---|
| HTTP host | `--http-host` | `0.0.0.0` | |
| HTTP port | `--http-port` | `8080` | |
| Database file | `--db-path` | — | Required for every command, `create-admin` included |
| JWT signing secret | `STRUCTURED_LOG_JWT_SECRET` / `…_FILE` | — | **Required for `serve`**, no flag, never generated |
| Token issuer | `--jwt-issuer` | `structured_log_server` | The `iss` claim embedded in access tokens |
| Ingestion body limit | `--max-ingest-body-bytes` | `10485760` (10 MiB) | Exceeding it is `413`, whole batch ([errors.md](../api/errors.md)) |
| Retention sweep interval | `--retention-purge-interval-seconds` | `3600` | How often the sweep runs; *what* it deletes is each project's own `retention_days` ([quotas-and-audit.md](../architecture/quotas-and-audit.md)) |
| Rate limiting | `--rate-limit-enabled` / `--no-rate-limit-enabled` | `true` | Turn off behind your own gateway ([auth.md](../architecture/auth.md#rate-limiting-throttling-without-lockout)) |
| Bucket capacity | `--rate-limit-bucket-capacity` | `10` | One value for both halves of the limiter: the IP bucket, spent on every request to a limited path, and the subject bucket, spent on failures only |
| Bucket refill | `--rate-limit-refill-per-minute` | `10` | Likewise shared by both; a successful login also refills that subject's bucket outright |
| Limiter key ceiling | `--rate-limit-max-keys` | `10000` | Per bucket store; LRU eviction above it |
| Trusted proxy hops | `--trusted-proxy-hops` | `0` | `0` = ignore `X-Forwarded-For` entirely |
| Live-stream heartbeat | `--sse-heartbeat-interval-seconds` | `25` | Also re-validates authorization ([live-streaming.md](../architecture/live-streaming.md)) |
| Own-log level | `--log-level` | `info` | One of `trace`/`debug`/`info`/`warning`/`error`/`critical`. The server's own diagnostics, not ingested entries ([README.md](../architecture/README.md#the-middleware-chain)) |
| Own-log format | `--log-format` | `console` | `console` or `json` for machine collection |
| Own-log file | `--log-file` | unset | Unset = console. When set, writing is asynchronous with rotation so it never blocks the single isolate |
| Own-log rotation size | `--log-max-file-bytes` | `10485760` (10 MiB) | Only meaningful together with `--log-file` |
| Own-log rotation count | `--log-max-files` | `5` | Likewise |
| Auto-bootstrap admin | `--bootstrap-admin-enabled` / `--no-bootstrap-admin-enabled` | `true` | Creates the first admin when the `users` table is empty ([rbac-and-lifecycle.md](../architecture/rbac-and-lifecycle.md#bootstrap-two-paths-to-the-first-admin)) |
| Bootstrap admin username | `--bootstrap-admin-username` | `admin` | The name auto-bootstrap uses, and the one `create-admin` creates |
| Bootstrap admin password | `STRUCTURED_LOG_BOOTSTRAP_ADMIN_PASSWORD` / `…_FILE` | generated | Secret: no flag. Unset = a random one is generated and printed once, marked temporary — for auto-bootstrap and `create-admin` alike |

<!-- /config-reference -->

### Not settings yet

These are specified in
[design.md](../../openspec/changes/add-structured-log-server/design.md)
but have **no flag and no environment variable today** — the capability
they configure has not shipped. Passing one is an unknown flag and stops
the launch; exporting the matching `STRUCTURED_LOG_*` variable earns an
"unrecognized environment variable" warning and is ignored. They are
listed so that the names, once they exist, are the names you already
planned around.

<!-- config-reference:planned -->

| Setting | Planned flag / variable | Today |
|---|---|---|
| Access token lifetime | `--access-token-ttl-seconds` | Fixed at 15 minutes in code |
| Refresh token lifetime | `--refresh-token-ttl-seconds` | Fixed at 30 days in code |
| Self-registration | `--registration-enabled` / `--no-registration-enabled` | No registration endpoint exists; the only way to add a user is an administrator ([auth.md](../architecture/auth.md)) |
| SMTP host / port | `--smtp-host`, `--smtp-port` | The server sends no email at all |
| SMTP username | `--smtp-username` | — |
| SMTP password | `STRUCTURED_LOG_SMTP_PASSWORD` / `…_FILE` | — |
| Sender address | `--smtp-from` | — |
| Password-reset link base | `--password-reset-base-url` | No password-reset flow |
| Password-reset token lifetime | `--password-reset-ttl-seconds` | — |
| Email-verification link base | `--email-verification-base-url` | No email-verification flow |
| Email-verification token lifetime | `--email-verification-ttl-seconds` | — |
| Audit retention | `--audit-retention-days` | Audit is Stage 2 ([design.md](../../openspec/changes/add-structured-log-server/design.md) "Delivery Phases"); nothing is recorded to retain |
| Auth-event retention | `--auth-event-retention-days` | Likewise |
| Audit purge chunk | `--audit-purge-batch-size` | Likewise. Log-entry purging already deletes in chunks, with a size fixed in code |

<!-- /config-reference -->

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
  dart run bin/server.dart --db-path ./dev.db --http-port 8080 --log-level debug
```

```bash
# Container: settings from the environment, secret from a mounted file
docker run \
  -e STRUCTURED_LOG_DB_PATH=/data/logs.db \
  -e STRUCTURED_LOG_HTTP_PORT=8080 \
  -e STRUCTURED_LOG_JWT_SECRET_FILE=/run/secrets/jwt \
  -e STRUCTURED_LOG_LOG_FORMAT=json \
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
# this command needs no JWT secret. The password is a secret, so it comes
# from the environment — omit it entirely to have one generated
STRUCTURED_LOG_BOOTSTRAP_ADMIN_PASSWORD_FILE=/run/secrets/admin-password \
  dart run bin/server.dart create-admin --db-path /data/logs.db \
  --bootstrap-admin-username admin
```

## See also

- [auth.md](../architecture/auth.md) — what the JWT secret and the rate
  limiter actually govern.
- [quotas-and-audit.md](../architecture/quotas-and-audit.md) — what the
  retention sweep deletes, and the per-project setting that decides it.
- [http-api.md](../api/http-api.md) — the endpoints these settings shape.
