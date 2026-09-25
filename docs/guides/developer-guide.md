# Developer Guide

*Читать на [русском](developer-guide.ru.md).*

For whoever writes code against `structured_log_server` from outside it
— sending an application's logs into it, or querying/live-tailing them
back out programmatically. If you don't need the server at all (just
`structured_log` and, optionally, an in-app viewer for your own
Flutter app), see the [Embedding Guide](embedding-guide.md) instead —
it's this guide's standalone counterpart. If you're deploying the
server itself, see the
[Administrator / DevOps Guide](admin-guide.md); if you're using the
admin client day to day, see the [User Guide](user-guide.md).

Two ways to integrate, roughly in order of how much of the system you
need to know:

1. **Ship logs to the server** — a Dart app uses
   [`structured_log`](#logging-with-structured_log) plus
   [`structured_log_http`](#sending-logs-to-the-server); anything else
   speaks the [ingestion HTTP endpoint](#from-any-other-language)
   directly.
2. **Read logs back out programmatically** — [query](#querying-logs)
   and [live-tail](#live-tailing-programmatically) over the same HTTP
   API the admin client uses.

## Logging with `structured_log`

The core library ([`emb/structured_log`](../../emb/structured_log/),
[published on pub.dev](https://pub.dev/packages/structured_log)) is
plain structured logging for Dart — zero runtime dependencies beyond
`meta`, and everything else in this guide builds on it:

```dart
import 'package:structured_log/structured_log.dart';

void main() {
  final log = getLogger();
  log.info('user_login', context: {'user_id': 42, 'ip': '127.0.0.1'});
}
```

`bind()` attaches context to a logger immutably (returns a new
instance); `withCorrelation()` binds a fixed, typed set of correlation
fields (`session_id`, `request_id`, `connection_generation`,
`tool_call_id`, `message_id`, `operation_id`) that the server's query
filters and the admin client's log browser both understand natively —
prefer these over ad-hoc context keys with the same meaning, so a
request can be traced end to end by one of these ids rather than a
field name that happens to match by convention:

```dart
final log = getLogger().withCorrelation(requestId: 'req-42');
log.info('request_started');
log.error('request_failed', context: {'status': 500});
```

Six levels, least to most severe: `trace` < `debug` < `info` <
`warning` < `error` < `critical`. Full API — processors, multi-sink
routing, file/rotating-file output — in
[`emb/structured_log/README.md`](../../emb/structured_log/README.md).

## Sending logs to the server

### From a Dart app: `structured_log_http`

[`structured_log_http`](../../emb/structured_log_http/) is an ordinary
`OutputFunction` — it plugs into a `LogSink` with no change to how you
call `structured_log` above, and it never blocks the calling code:
entries are queued and shipped on a background future.

```dart
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_http/structured_log_http.dart';

final output = HttpLogOutput(
  serverUrl: 'https://logs.example.com',
  projectSecretKey: 'slk_...',    // from an owner/admin, see below
);

StructlogConfiguration.configure(
  sinks: [LogSink(name: 'server', output: output)],
);

getLogger().info('startup', context: {'version': '1.4.0'});

// Await before process exit — otherwise queued entries can be lost.
await output.flushed;
```

Getting a project secret key is a one-time setup step someone with
`owner`/`admin` access does in the admin client (**Groups → a project →
Secret keys → Create**) or via `POST /v1/projects/:id/secret-keys` —
the value is shown exactly once, at creation; store it the same way
you'd store any other application secret (an env var, a mounted secret
file — never committed to source control).

What you get for free:

- **Batching** by size or timeout, whichever comes first.
- **Retry with backoff** on network failures/timeouts/5xx, never on a
  4xx — a revoked key answers 401 forever, so retrying it only delays
  what's queued behind it.
- **Buffer eviction**: a bounded in-memory buffer drops the *oldest*
  unsent entries first if the server is unreachable for a while — an
  unbounded queue would turn a logging outage into an application
  outage, which is backwards.
- **Failure reporting**: failures go to `stderr` rather than being
  thrown — nothing this package does can make a `log.info(...)` call
  itself fail.

Full parameter reference:
[`emb/structured_log_http/README.md`](../../emb/structured_log_http/README.md).

Keep a console sink alongside the server sink during development — each
filters independently, so you see everything locally while only
shipping `info`-and-above to the server, for example:

```dart
StructlogConfiguration.configure(sinks: [
  LogSink(name: 'console', output: coloredConsoleOutput),
  LogSink(name: 'server', output: output, minLevel: LogLevel.info),
]);
```

### From any other language

There's no requirement to use `structured_log` at all — `POST /v1/logs`
is a plain HTTP endpoint. Authenticate with the project's secret key,
send a JSON array of entries, done:

```bash
curl -X POST https://logs.example.com/v1/logs \
  -H "Authorization: Bearer slk_..." \
  -H "Content-Type: application/json" \
  -d '[
    {"event": "payment_failed", "level": "error",
     "timestamp": "2026-03-05T14:29:59.981Z",
     "category": "checkout", "order_id": "ord_44821"},
    {"event": "request_completed", "level": "info",
     "timestamp": "2026-03-05T14:30:00.100Z"}
  ]'
```

An entry is a free-form JSON object. Only `event`, `level`, and
`timestamp` carry fixed meaning (`level` must be one of `trace`/`debug`/
`info`/`warning`/`error`/`critical`); everything else — `category`, `logger`,
the six correlation fields, and any custom key at all — is optional and
preserved exactly as sent, byte for byte, in every later query response.
**Don't send `id`, `project_id`, or `received_at`** — those three names
are reserved for server-assigned fields on the way back out, and an
entry containing any of them is rejected (that one entry only, not the
whole batch).

The response is always `202`, even if some or all entries were
rejected — the request itself succeeded; per-entry outcomes are in the
body:

```json
{
  "accepted": 8,
  "rejected": [
    {"index": 3, "error": "validation_error", "message": "level: must be one of trace, debug, info, warning, error, critical"},
    {"index": 7, "error": "quota_exceeded", "message": "project max_entries limit reached"}
  ]
}
```

Check `rejected` if you care about individual failures — a client that
only checks the HTTP status will miss them. The only ways this endpoint
answers a top-level *error* instead are: an invalid/unknown/revoked
secret key (`401`), the project itself blocked (`403 project_blocked`,
whole batch, nothing evaluated), or the request body over the
configured size limit (`413`, whole batch).

**Batch, don't send one entry per request.** There's no artificial
floor on batch size, but each request has fixed overhead independent of
how many entries it carries — an application generating more than a
handful of log lines a second should accumulate and send them together,
which is exactly what `structured_log_http` does automatically if
you're in Dart.

## Querying logs

`GET /v1/logs`, authenticated with a person's **access token** (not a
project secret key — the two credentials are not interchangeable, and
presenting the wrong one for an endpoint answers `401` exactly like a
missing one does). See
[Authenticating as a person](#authenticating-as-a-person) below for how
to get one.

```bash
curl -G https://logs.example.com/v1/logs \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -d project_id=7 \
  -d level=warning \
  -d from=2026-03-05T00:00:00Z \
  -d limit=50
```

Exactly one of `project_id`/`group_id` is required (a group query
spans every project in it); optional filters include `level` (minimum,
inclusive), `category`/`logger` (exact match), `from`/`to` (a range on
`timestamp`), any of the six correlation fields (exact match), `q`
(full-text, matched against the event and content), and
`context.<key>=<value>` for an exact match on any custom field you
sent, e.g. `context.order_id=ord_44821`.

**Pagination**: `{"items": [...], "next_cursor": "<string, nullable>"}`
— newest first by `id`; pass `next_cursor` back as `cursor` for the
next page. `next_cursor: null` means you've reached the end; there's no
`total` count (counting the full result set costs more than the number
is worth at this scale). `limit` defaults to 50 and is silently capped
at 200 rather than rejected if you ask for more.

Full parameter and response reference:
[api/http-api.md](../api/http-api.md#get-v1logs),
[api/models.md#logentry](../api/models.md#logentry).

## Live-tailing programmatically

`GET /v1/logs/stream` — same filters as `GET /v1/logs` above, plus
`since_id` to seamlessly bridge the gap between the last page you
rendered and when the subscription opens (query it with the last `id`
you saw; the server backfills anything missed, then continues live,
with no loss and no duplicates). It's Server-Sent Events, a plain HTTP
response with a streamed body — no WebSocket handshake, no separate
protocol:

```bash
curl -N https://logs.example.com/v1/logs/stream \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -G -d project_id=7 -d level=warning
```

```text
: connected

id: 918273
event: log
data: {"event": "payment_failed", "level": "error", ...}

: ping
```

`data:` carries one [`LogEntry`](../api/models.md#logentry) as JSON,
the same shape `GET /v1/logs` returns. `: ping` comments arrive every
`--sse-heartbeat-interval-seconds` (25s by default) as a keep-alive —
ignore lines starting with `:`. **Authorization is re-checked on every
heartbeat, not just at connect time**: if your access is revoked or the
project gets blocked while the connection is open, you'll see a
terminal `event: end` frame (`data: {"reason": "token_revoked"}` or
`"project_blocked"`) rather than the connection silently going quiet —
treat that exactly like an out-of-band `401`/`403` and reconnect
through a fresh token if appropriate.

**Why not browser `EventSource`:** it can't send an `Authorization`
header, and a token in the URL's query string would end up in proxy and
server logs — so a browser client needs to read the stream via
`fetch`/`ReadableStream` (or an equivalent streaming HTTP client) with
the header set explicitly, the same way `structured_log_admin_client`
does it, rather than the native `EventSource` API.

## Authenticating as a person

The management/query API (everything except `POST /v1/logs`, which
uses a project secret key instead) uses short-lived JWT (JSON Web
Token) access tokens, issued through a standard OAuth2 password-grant
endpoint (`POST /v1/auth/token`). The endpoint's shape closely follows
Keycloak's token endpoint — closely enough that an off-the-shelf
OAuth2 client library can talk to it — but no Keycloak or other
identity provider actually sits behind it:

```bash
# Form-encoded (RFC 6749), not JSON — the one endpoint in this API that departs
# from the general JSON envelope, specifically for OAuth2-client compatibility.
curl -X POST https://logs.example.com/v1/auth/token \
  -d grant_type=password -d username=alice -d password='...'
```

```json
{"access_token": "eyJ...", "refresh_token": "...", "token_type": "Bearer", "expires_in": 900, "refresh_expires_in": 2592000}
```

The access token is short-lived by design (15 minutes; the refresh
token lasts 30 days — both fixed, not currently exposed as a config
setting) — when a request answers `401`, refresh rather than
re-prompting for a password:

```bash
curl -X POST https://logs.example.com/v1/auth/token \
  -d grant_type=refresh_token -d refresh_token=$REFRESH_TOKEN
```

Revoke a session explicitly with `DELETE /v1/auth/token` (RFC 7009 —
always answers `200`, whether or not the token was actually valid, so
the response can't be used to probe someone else's session). There is
**no self-service account creation** — every account is created by an
administrator or a group owner (`POST /v1/users`); build your
integration around that, not around a registration flow, since
`POST /v1/auth/register` doesn't exist in this deployment (see
[What isn't implemented](#what-isnt-implemented) below).

A first-time or admin-reset account is marked
`must_change_password: true` — every endpoint except
`POST /v1/auth/change-password` (and a small allowlist covering
session maintenance and self-deletion) answers
`403 must_change_password` until it's cleared. If you're automating
account provisioning, plan for this step rather than treating a fresh
account as immediately usable for anything but changing its own
password.

One thing to get right while automating that step: a successful
`POST /v1/auth/change-password` revokes the account's refresh tokens.
Pass the refresh token you are holding as `current_refresh_token` and
the session you are using survives; omit it and your own script is
signed out along with everything else, because the server has no other
way to tell which session is asking. `keep_other_sessions: true` skips
the revocation entirely — reasonable for a provisioning script setting
up an account nobody is signed in to yet.

Full contract, including the `token_version` revocation mechanism and
error shapes: [architecture/auth.md](../architecture/auth.md),
[api/errors.md](../api/errors.md).

## Calling the management API

Everything the admin client's UI does — creating groups/projects/teams,
rotating secret keys, granting roles, managing users, reading the audit
log — is one documented HTTP endpoint each, listed in full in
[api/http-api.md](../api/http-api.md). A few worth knowing about if
you're scripting provisioning:

```bash
# Create a project inside a group you own/administer
curl -X POST https://logs.example.com/v1/groups/3/projects \
  -H "Authorization: Bearer $ACCESS_TOKEN" -H "Content-Type: application/json" \
  -d '{"name": "checkout-service", "retention_days": 30, "max_entries": 1000000}'

# Mint a secret key for it (the *only* time its value is returned)
curl -X POST https://logs.example.com/v1/projects/7/secret-keys \
  -H "Authorization: Bearer $ACCESS_TOKEN" -H "Content-Type: application/json" \
  -d '{"label": "ci-pipeline"}'

# Grant a user read access to it
curl -X POST https://logs.example.com/v1/role-assignments \
  -H "Authorization: Bearer $ACCESS_TOKEN" -H "Content-Type: application/json" \
  -d '{"subject_type": "user", "subject_id": 42, "role": "user", "scope_type": "project", "scope_id": 7}'
```

`subject_type` is `user` or `team`; `scope_type` is `group` or
`project` — see
[api/http-api.md](../api/http-api.md#post-v1role-assignments) for the
full set.

Role rules mirror what's in the [User Guide](user-guide.md#what-your-role-lets-you-do):
`admin` reaches everything; `owner` can act within groups they own
(and can grant `owner`/`user` there, never `admin`); `user` is
read-only. A caller's token carries a snapshot of their effective roles
at issuance — see [architecture/auth.md](../architecture/auth.md) if
you're building something that needs to reason about *when* a
permission change takes effect for an already-issued token.

## Error handling

Every endpoint except the token endpoint uses one JSON envelope:

```json
{"error": "validation_error", "message": "human-readable text", "details": {"...": "optional, code-specific"}}
```

The token endpoint alone answers in RFC 6749 §5.2's shape
(`{"error": "invalid_grant", "error_description": "..."}`) for
OAuth2-client compatibility — don't assume `error`/`message` on that
one endpoint specifically. `429 too_many_requests` (rate limiting, on
auth endpoints only) carries a standard `Retry-After` header and means
the action genuinely didn't happen — safe to retry after the interval.
Full catalog, every status/code pair and where each can occur:
[api/errors.md](../api/errors.md).

## Embedding a live viewer in a Flutter app

Unrelated to `structured_log_http` above and entirely local, no server
involved — see the [Embedding Guide](embedding-guide.md#2-a-headless-viewer-core-structured_log_flutter)
for the three ready-made viewer skins. You can use one, the other, both
together (mirror the same entries to a local in-app viewer *and* ship
them to the server), or neither.

## Rate limits and good citizenship

Only the authentication endpoints are rate-limited (login, password
change, and similarly sensitive actions) — `POST /v1/logs` is governed
by the project's quota and its secret key, not request frequency, and
management endpoints are governed by role-based access, not a request
counter. There's no cap on how often you may call `GET /v1/logs` or
open a stream beyond what your own infrastructure and the server's
resources can sustain — batch ingestion sensibly (above), and prefer
one long-lived `GET /v1/logs/stream` connection over polling `GET
/v1/logs` in a tight loop if you need near-real-time updates.

## What isn't implemented

Documented for completeness, because you may encounter them described
elsewhere in this repository's design documents: self-service
registration (`POST /v1/auth/register`), self-service password reset by
email, and mandatory email verification are part of the originally
proposed design and appear in
[architecture/auth.md](../architecture/auth.md) and (for now) in
[api/http-api.md](../api/http-api.md), but none of the three exist in
the running server — there is no such route. Every account is created
by an administrator or a group owner, and a forgotten password is reset
the same way (`PATCH /v1/users/:id`), not recovered by the user
themselves.

## Where to go next

- [Embedding Guide](embedding-guide.md) — `structured_log` on its own,
  and the in-app viewer widgets, with no server involved.
- [api/http-api.md](../api/http-api.md) — every endpoint, exhaustively.
- [api/models.md](../api/models.md) — every JSON object shape.
- [api/errors.md](../api/errors.md) — the complete error catalog.
- [architecture/](../architecture/) — *why* the contract is shaped this
  way, if you need to reason about edge cases the reference alone
  doesn't explain (token revocation timing, what blocking a project
  does mid-stream, and so on).
