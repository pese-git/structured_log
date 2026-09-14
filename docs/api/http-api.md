# HTTP API reference

*Читать на [русском](http-api.ru.md).*

Every `structured_log_server` endpoint: parameters, request/response
bodies, the specific errors each one can return, and a `curl` example.
Shared object shapes live in [models.md](models.md); the full error
catalog (shared across endpoints) lives in [errors.md](errors.md) — this
document links to both rather than repeating them per endpoint.

This is a reading aid over the normative OpenSpec artifacts, not a
replacement for them — `specs/*.md` describe required *behavior*
(SHALL statements + scenarios); this document commits to the concrete
wire-level shapes (exact field names, envelopes, pagination mechanics)
needed to write a client or a `curl` request, filling in details the
specs deliberately leave at "a JSON object identifying the error." If
`specs/*.md` is ever revised with a conflicting shape, that wins and
this page should follow.

Examples below use `http://localhost:8080` as the server's base URL,
and shell variables `$ACCESS_TOKEN` (a JWT from `POST /v1/auth/token`)
and `$PROJECT_SECRET_KEY` (from `POST /v1/projects/:id/secret-keys`) —
substitute your own.

## Log ingestion, query, and live stream (`log-server-api`, `log-server-live-stream`)

Spec:
[specs/log-server-api/spec.md](../../openspec/changes/add-structured-log-server/specs/log-server-api/spec.md),
[specs/log-server-live-stream/spec.md](../../openspec/changes/add-structured-log-server/specs/log-server-live-stream/spec.md).

### `POST /v1/logs`

Auth: `Authorization: Bearer <project-secret-key>`.

**Request body:** JSON array of free-form log-entry objects — see
[models.md#logentry](models.md#logentry). No wrapper object; the array
is the entire body.

**Response `202`:** [Ingestion response](models.md#ingestion-response)
— always `202` if the request itself is well-formed/authenticated/
under the size limit and the project isn't blocked, even if every entry
was rejected; see [errors.md](errors.md#partial-batch-acceptance-is-not-an-error).

**Errors:** `401 unauthorized` (bad/unknown/revoked key), `403
project_blocked`, `413 payload_too_large`. Per-entry `validation_error`/
`quota_exceeded` are reported inside the `202` body, not as HTTP errors.

```bash
curl -X POST http://localhost:8080/v1/logs \
  -H "Authorization: Bearer $PROJECT_SECRET_KEY" \
  -H "Content-Type: application/json" \
  -d '[
    {"event": "payment_failed", "level": "error", "timestamp": "2026-03-05T14:29:59.981Z",
     "category": "checkout", "order_id": "ord_44821"},
    {"event": "request_completed", "level": "info", "timestamp": "2026-03-05T14:30:00.100Z"}
  ]'
```

### `GET /v1/logs`

Auth: `Authorization: Bearer <access-token>`.

**Query parameters:**

| Param | Type | Notes |
|---|---|---|
| `project_id` **xor** `group_id` | integer | Exactly one required |
| `level` | string | Minimum level (inclusive) |
| `category`, `logger` | string | Exact match |
| `from`, `to` | ISO 8601 | Range on `timestamp` |
| `session_id`, `request_id`, `connection_generation`, `tool_call_id`, `message_id`, `operation_id` | string | Exact match |
| `q` | string | Full-text, matched against `event` and content |
| `context.<key>` | string | Exact match on a custom field, e.g. `context.order_id=ord_44821` |
| `limit` | integer | Page size |
| `cursor` | string | From a previous response's `next_cursor` |

**Response `200`:** `{"items": [LogEntry], "next_cursor": string \| null}` — see [models.md#logentry](models.md#logentry). Without `cursor`, `items` is ordered newest-first by `id`; `cursor` advances toward older entries.

**Errors:** `403 forbidden` (no grant covering the scope), `403 project_blocked` (direct `project_id` only — a `group_id` query silently drops the blocked project's entries instead), `404 not_found` (`project_id`/`group_id` doesn't exist).

```bash
curl -G http://localhost:8080/v1/logs \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -d project_id=7 \
  -d level=warning \
  -d from=2026-03-05T00:00:00Z \
  -d limit=50
```

### `GET /v1/logs/stream`

Auth: `Authorization: Bearer <access-token>`.

**Query parameters:** same as `GET /v1/logs` above, plus `since_id`
(integer, optional — catch-up cutoff, see
[live-streaming.md](../architecture/live-streaming.md#bridging-the-gap-since_id-catch-up)).
No `limit`/`cursor` — this is a stream, not a page.

**Response `200`:** `Content-Type: text/event-stream`; frames are `id:
<log entry id>` / `event: log` / `data: <LogEntry as JSON>`, plus
periodic `: ping` keep-alive comments and a possible terminal `event:
end` — full framing in [live-streaming.md](../architecture/live-streaming.md).

**Errors:** same as `GET /v1/logs`, returned as a normal (non-streamed)
response *before* the connection upgrades — a rejected subscription
never opens a stream that then errors.

```bash
curl -N http://localhost:8080/v1/logs/stream \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -G -d project_id=7 -d level=warning
```

### `GET /healthz`

Auth: none.

**Response `200`:** `{"status": "ok"}`.

**Errors:** none defined — the endpoint doesn't respond (connection
refused/timeout) rather than returning an error status while the server
isn't ready.

```bash
curl http://localhost:8080/healthz
```

## Authentication and password recovery (`log-server-auth`, `log-server-password-reset`)

Spec:
[specs/log-server-auth/spec.md](../../openspec/changes/add-structured-log-server/specs/log-server-auth/spec.md),
[specs/log-server-password-reset/spec.md](../../openspec/changes/add-structured-log-server/specs/log-server-password-reset/spec.md),
[specs/log-server-email-verification/spec.md](../../openspec/changes/add-structured-log-server/specs/log-server-email-verification/spec.md).
See [auth.md](../architecture/auth.md).

**Every endpoint in this section is rate-limited**
(`log-server-rate-limit`), along with `POST /v1/auth/change-password`
and `DELETE /v1/users/me`: a rejected request answers `429
too_many_requests` with a `Retry-After` header and the *general* JSON
envelope — including the token endpoint, the one place it departs from
the RFC 6749 shape ([errors.md](errors.md#429-is-the-one-non-rfc-answer-the-token-endpoint-gives)).
A `429` means the action never ran: no password was checked, no token
issued, no email sent, and no account was locked
([auth.md](../architecture/auth.md#rate-limiting-throttling-without-lockout)).
The error lists below don't repeat `429` per endpoint.

### `POST /v1/auth/register`

Auth: none. JSON body, **not** form-encoded — unlike the token endpoint
below, this path isn't part of the RFC 6749 token contract, so it
follows this API's normal JSON convention.

**Request body:**

| Field | Type | Required |
|---|---|---|
| `username` | string | yes |
| `password` | string | yes |
| `email` | string | yes — mandatory on this path specifically |
| `display_name` | string | no |

**Response `201`:** [User](models.md#user) (no `RoleAssignment` yet, `email_verified_at: null`). A verification email is sent as a side effect — the account cannot log in via `grant_type=password` until it's confirmed, see below and [auth.md](../architecture/auth.md#email-verification-mandatory-before-login-not-optional).

**Errors:** `400 invalid_request` (missing `email`/`username`/`password`), `403 forbidden` (`registrationEnabled = false`), `409 username_taken`, `409 email_taken`.

```bash
curl -X POST http://localhost:8080/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{"username": "alice", "password": "correct-horse-battery-staple", "email": "alice@example.com"}'
```

### `POST /v1/auth/verify-email`

Auth: none (the verification token is the credential). JSON body.

**Request body:** `{"token": "..."}`

**Response `200`:** `{}`. Sets `email_verified_at`, after which `grant_type=password` works normally for this account.

**Errors:** `400 invalid_token` (unknown/expired/already-used token).

```bash
curl -X POST http://localhost:8080/v1/auth/verify-email \
  -H "Content-Type: application/json" \
  -d '{"token": "a1b2c3..."}'
```

### `POST /v1/auth/verify-email/resend`

Auth: none. JSON body.

**Request body:** `{"email": "..."}`

**Response `202`:** `{}` — always, regardless of whether the email is registered or already verified (anti-enumeration, same pattern as `password-reset`).

**Errors:** `400 invalid_request` (missing `email`).

```bash
curl -X POST http://localhost:8080/v1/auth/verify-email/resend \
  -H "Content-Type: application/json" \
  -d '{"email": "alice@example.com"}'
```

### `POST /v1/auth/token`

Auth: none. **Form-encoded** (`application/x-www-form-urlencoded`),
RFC 6749 — the one endpoint in this API that deviates from the general
JSON envelope on both request and error response, for compatibility
with off-the-shelf OAuth2 clients ([auth.md](../architecture/auth.md)).

**Request body (`grant_type=password`):** `grant_type=password&username=...&password=...`

**Request body (`grant_type=refresh_token`):** `grant_type=refresh_token&refresh_token=...`

**Response `200`:** [Token response](models.md#token-response).

**Errors:** `429 too_many_requests` (general envelope, see above); otherwise all `400`, RFC shape — `invalid_request` (missing field for the given `grant_type`), `unsupported_grant_type`, `invalid_grant` (wrong credentials; unknown/expired/revoked refresh token; blocked user on refresh; unverified `email` on `grant_type=password` — response additionally carries `reason: "email_not_verified"`, see [errors.md](errors.md#extending-the-token-endpoints-rfc-envelope-reason)).

```bash
curl -X POST http://localhost:8080/v1/auth/token \
  -d grant_type=password \
  -d username=alice \
  -d password=correct-horse-battery-staple
```

```bash
curl -X POST http://localhost:8080/v1/auth/token \
  -d grant_type=refresh_token \
  -d refresh_token=$REFRESH_TOKEN
```

### `DELETE /v1/auth/token`

Auth: none (the refresh token being revoked is the credential). Form-encoded, RFC 7009.

**Request body:** `refresh_token=...`

**Response `200`:** `{}` — always, whether or not the token was valid (anti-enumeration, [auth.md](../architecture/auth.md)).

**Errors:** `400 invalid_request` (RFC shape) only if the `refresh_token` field itself is missing from the body.

```bash
curl -X DELETE http://localhost:8080/v1/auth/token \
  -d refresh_token=$REFRESH_TOKEN
```

### `POST /v1/auth/password-reset`

Auth: none. JSON body.

**Request body:** `{"email": "..."}`

**Response `202`:** `{}` — always, regardless of whether the email is registered (anti-enumeration).

**Errors:** `400 invalid_request` (missing `email`).

```bash
curl -X POST http://localhost:8080/v1/auth/password-reset \
  -H "Content-Type: application/json" \
  -d '{"email": "alice@example.com"}'
```

### `POST /v1/auth/password-reset/confirm`

Auth: none (the reset token is the credential). JSON body.

**Request body:** `{"token": "...", "new_password": "..."}`

**Response `200`:** `{}`.

**Errors:** `400 invalid_token` (unknown/expired/already-used token), `400 invalid_request` (missing field).

```bash
curl -X POST http://localhost:8080/v1/auth/password-reset/confirm \
  -H "Content-Type: application/json" \
  -d '{"token": "a1b2c3...", "new_password": "even-better-passphrase"}'
```

### `DELETE /v1/users/me`

Auth: `Authorization: Bearer <access-token>`. JSON body.

**Request body:** `{"password": "..."}`

**Response `204`:** empty body.

**Errors:** `401 invalid_grant` (wrong password), `403 cannot_delete_primary_admin`, `409 sole_group_owner` (`details.blocking_groups`).

```bash
curl -X DELETE http://localhost:8080/v1/users/me \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"password": "correct-horse-battery-staple"}'
```

### `POST /v1/auth/change-password`

Auth: `Authorization: Bearer <access-token>`. JSON body. Available to
any authenticated role, over their own account only — not just while
`must_change_password` is set (`log-server-forced-password-change`,
[auth.md](../architecture/auth.md#patch-v1usersid-and-the-mandatory-temporary-password)).

**Request body:** `{"current_password": "...", "new_password": "..."}`

**Response `200`:** `{}`. Clears `must_change_password` if it was set.

**Errors:** `401 invalid_grant` (wrong current password).

```bash
curl -X POST http://localhost:8080/v1/auth/change-password \
  -H "Authorization: Bearer $ACCESS_TOKEN" -H "Content-Type: application/json" \
  -d '{"current_password": "temp-password-123", "new_password": "a-much-better-passphrase"}'
```

## Users, groups, teams, roles (`log-server-rbac`)

Spec:
[specs/log-server-rbac/spec.md](../../openspec/changes/add-structured-log-server/specs/log-server-rbac/spec.md),
[specs/log-server-forced-password-change/spec.md](../../openspec/changes/add-structured-log-server/specs/log-server-forced-password-change/spec.md).
See [rbac-and-lifecycle.md](../architecture/rbac-and-lifecycle.md). All
endpoints below: `Authorization: Bearer <access-token>`, JSON bodies.

### `POST /v1/users`

Role: `admin`.

**Request body:** same fields as `POST /v1/auth/register`, but `email` is optional here.

**Response `201`:** [User](models.md#user) — `must_change_password: true` always (`log-server-forced-password-change`); `email_verified_at: null` if `email` was set.

**Errors:** `403 forbidden`, `409 username_taken`, `409 email_taken`.

```bash
curl -X POST http://localhost:8080/v1/users \
  -H "Authorization: Bearer $ACCESS_TOKEN" -H "Content-Type: application/json" \
  -d '{"username": "bob", "password": "temp-password-123", "display_name": "Bob Diaz"}'
```

### `GET /v1/users`

Role: `admin`.

**Query:** `limit`, `cursor`.

**Response `200`:** `{"items": [User], "next_cursor": string \| null}`.

**Errors:** `403 forbidden`.

```bash
curl -G http://localhost:8080/v1/users -H "Authorization: Bearer $ACCESS_TOKEN" -d limit=50
```

### `PATCH /v1/users/:id`

Role: `admin`. Partial update — any subset of the fields below.

**Request body:**

| Field | Type | Notes |
|---|---|---|
| `email` | string | A new value resets `email_verified_at` to `null` and triggers a fresh verification email |
| `display_name` | string | |
| `password` | string | Setting this always sets `must_change_password: true` and revokes all of the target's refresh tokens |

**Response `200`:** [User](models.md#user) (updated).

**Errors:** `403 forbidden`, `404 not_found`, `409 email_taken`.

```bash
curl -X PATCH http://localhost:8080/v1/users/42 \
  -H "Authorization: Bearer $ACCESS_TOKEN" -H "Content-Type: application/json" \
  -d '{"password": "new-temp-password-456"}'
```

### `POST /v1/users/:id/block` / `POST /v1/users/:id/unblock`

Role: `admin`. No request body.

**Response `200`:** [User](models.md#user) (updated `is_active`).

**Errors:** `403 forbidden`, `404 not_found`; `unblock` additionally: `409 deleted_account`.

```bash
curl -X POST http://localhost:8080/v1/users/42/block -H "Authorization: Bearer $ACCESS_TOKEN"
curl -X POST http://localhost:8080/v1/users/42/unblock -H "Authorization: Bearer $ACCESS_TOKEN"
```

### `DELETE /v1/users/:id`

Role: `admin`. No request body — target's password is never required.

**Response `204`:** empty body.

**Errors:** `400 self_deletion_requires_me` (`:id == caller`), `403 forbidden`, `403 cannot_delete_primary_admin`, `404 not_found`, `409 sole_group_owner`.

```bash
curl -X DELETE http://localhost:8080/v1/users/99 -H "Authorization: Bearer $ACCESS_TOKEN"
```

### `POST /v1/groups`

Role: `admin`.

**Request body:** `{"name": "..."}`

**Response `201`:** [Group](models.md#group).

**Errors:** `403 forbidden`.

```bash
curl -X POST http://localhost:8080/v1/groups \
  -H "Authorization: Bearer $ACCESS_TOKEN" -H "Content-Type: application/json" \
  -d '{"name": "payments-team"}'
```

### `GET /v1/groups`

Role: any authenticated user; results scoped to visible groups.

**Response `200`:** `{"items": [Group]}`.

```bash
curl http://localhost:8080/v1/groups -H "Authorization: Bearer $ACCESS_TOKEN"
```

### `POST /v1/groups/:groupId/teams`

Role: `owner` of `:groupId`, or `admin`.

**Request body:** `{"name": "..."}`

**Response `201`:** [Team](models.md#team).

**Errors:** `403 forbidden`, `404 not_found` (`:groupId`).

```bash
curl -X POST http://localhost:8080/v1/groups/3/teams \
  -H "Authorization: Bearer $ACCESS_TOKEN" -H "Content-Type: application/json" \
  -d '{"name": "on-call"}'
```

### `POST /v1/teams/:teamId/members`

Role: `owner` of the team's group, or `admin`. Bumps `token_version`
for every current member of the team ([auth.md](../architecture/auth.md#token_version-how-a-snapshot-in-a-jwt-stays-revocable)).

**Request body:** `{"user_id": 42}`

**Response `204`:** empty body.

**Errors:** `403 forbidden`, `404 not_found` (`:teamId` or `user_id`).

```bash
curl -X POST http://localhost:8080/v1/teams/5/members \
  -H "Authorization: Bearer $ACCESS_TOKEN" -H "Content-Type: application/json" \
  -d '{"user_id": 42}'
```

### `DELETE /v1/teams/:teamId/members/:userId`

Role: `owner` of the team's group, or `admin`. Same `token_version` effect as above.

**Response `204`:** empty body.

**Errors:** `403 forbidden`, `404 not_found`.

```bash
curl -X DELETE http://localhost:8080/v1/teams/5/members/42 -H "Authorization: Bearer $ACCESS_TOKEN"
```

### `POST /v1/role-assignments`

Role: `admin` (any grant), or `owner` (`owner`/`user` within their own group/its projects only).

**Request body:**

| Field | Type | Notes |
|---|---|---|
| `subject_type` | `"user"` \| `"team"` | |
| `subject_id` | integer | |
| `role` | `"admin"` \| `"owner"` \| `"user"` | |
| `scope_type` | `"global"` \| `"group"` \| `"project"` | |
| `scope_id` | integer | Required unless `scope_type: "global"` |

**Response `201`:** [RoleAssignment](models.md#roleassignment).

**Errors:** `400 invalid_request`, `403 forbidden` (including an `owner` attempting `role: admin`, or a scope outside their own group), `404 not_found` (`subject_id`/`scope_id`).

```bash
curl -X POST http://localhost:8080/v1/role-assignments \
  -H "Authorization: Bearer $ACCESS_TOKEN" -H "Content-Type: application/json" \
  -d '{"subject_type": "user", "subject_id": 42, "role": "user", "scope_type": "project", "scope_id": 7}'
```

### `DELETE /v1/role-assignments/:id`

Role: same rule as creating it.

**Response `204`:** empty body.

**Errors:** `403 forbidden`, `404 not_found`.

```bash
curl -X DELETE http://localhost:8080/v1/role-assignments/128 -H "Authorization: Bearer $ACCESS_TOKEN"
```

## Projects and quotas (`log-server-rbac`, `log-server-quotas`)

Spec:
[specs/log-server-quotas/spec.md](../../openspec/changes/add-structured-log-server/specs/log-server-quotas/spec.md).
See [quotas-and-audit.md](../architecture/quotas-and-audit.md). All
endpoints: `Authorization: Bearer <access-token>`, JSON bodies.

### `POST /v1/groups/:groupId/projects`

Role: `owner` of `:groupId`, or `admin`.

**Request body:**

| Field | Type | Required |
|---|---|---|
| `name` | string | yes |
| `retention_days` | integer | yes |
| `max_entries` | integer | no |
| `max_bytes` | integer | no |

**Response `201`:** [Project](models.md#project) (without `entry_count`/`total_bytes`).

**Errors:** `400 invalid_request` (missing `retention_days`), `403 forbidden`, `404 not_found` (`:groupId`).

```bash
curl -X POST http://localhost:8080/v1/groups/3/projects \
  -H "Authorization: Bearer $ACCESS_TOKEN" -H "Content-Type: application/json" \
  -d '{"name": "checkout-service", "retention_days": 30, "max_entries": 1000000}'
```

### `PATCH /v1/projects/:id`

Role: `owner`/`admin`.

**Request body:** any of `retention_days`/`max_entries`/`max_bytes` (partial update).

**Response `200`:** [Project](models.md#project) (updated, without `entry_count`/`total_bytes`).

**Errors:** `403 forbidden`, `404 not_found`.

```bash
curl -X PATCH http://localhost:8080/v1/projects/7 \
  -H "Authorization: Bearer $ACCESS_TOKEN" -H "Content-Type: application/json" \
  -d '{"max_entries": 2000000}'
```

### `GET /v1/projects/:id`

Role: `owner`/`user` with access, or `admin`.

**Response `200`:** [Project](models.md#project), **with** `entry_count`/`total_bytes`.

**Errors:** `403 forbidden`, `404 not_found`.

```bash
curl http://localhost:8080/v1/projects/7 -H "Authorization: Bearer $ACCESS_TOKEN"
```

### `POST /v1/projects/:id/block` / `POST /v1/projects/:id/unblock`

Role: `admin` only — not `owner`, even for their own project. No request body.

**Response `200`:** [Project](models.md#project) (updated `is_blocked`).

**Errors:** `403 forbidden`, `404 not_found`.

```bash
curl -X POST http://localhost:8080/v1/projects/7/block -H "Authorization: Bearer $ACCESS_TOKEN"
curl -X POST http://localhost:8080/v1/projects/7/unblock -H "Authorization: Bearer $ACCESS_TOKEN"
```

### `POST /v1/projects/:id/secret-keys`

Role: `owner`/`admin`.

**Request body:** `{"label": "..."}` (optional).

**Response `201`:** [ProjectSecretKey](models.md#projectsecretkey), **with** `secret` — shown exactly this once.

**Errors:** `403 forbidden`, `404 not_found`.

```bash
curl -X POST http://localhost:8080/v1/projects/7/secret-keys \
  -H "Authorization: Bearer $ACCESS_TOKEN" -H "Content-Type: application/json" \
  -d '{"label": "prod-checkout-instance-1"}'
```

### `GET /v1/projects/:id/secret-keys`

Role: `owner`/`admin`.

**Response `200`:** `{"items": [ProjectSecretKey]}` — metadata only, never `secret`.

**Errors:** `403 forbidden`, `404 not_found`.

```bash
curl http://localhost:8080/v1/projects/7/secret-keys -H "Authorization: Bearer $ACCESS_TOKEN"
```

### `DELETE /v1/projects/:id/secret-keys/:keyId`

Role: `owner`/`admin`. Irreversible.

**Response `204`:** empty body.

**Errors:** `403 forbidden`, `404 not_found`.

```bash
curl -X DELETE http://localhost:8080/v1/projects/7/secret-keys/15 -H "Authorization: Bearer $ACCESS_TOKEN"
```

## Audit log (`log-server-audit`)

Spec:
[specs/log-server-audit/spec.md](../../openspec/changes/add-structured-log-server/specs/log-server-audit/spec.md).
See [quotas-and-audit.md](../architecture/quotas-and-audit.md#audit-log-log-server-audit).

### `GET /v1/audit-log`

Auth: `Authorization: Bearer <access-token>`. Role: `admin` only — not `owner`.

**Query parameters:** `actor_user_id`, `action`, `target_type`, `target_id`, `from`, `to`, `limit`, `cursor`.

**Response `200`:** `{"items": [AuditLogEntry], "next_cursor": string \| null, "audit_retention_days": integer \| null, "auth_event_retention_days": integer \| null}` — the two retention fields report the policy in force (`null` = kept indefinitely), so an empty result outside the window explains itself ([quotas-and-audit.md](../architecture/quotas-and-audit.md#audit-log-log-server-audit)).

**Errors:** `403 forbidden`.

There is no endpoint that deletes audit entries, for any role, and the retention periods are set in the server's configuration rather than through the API — an admin is a subject of this log, not its owner. Entries disappear only through the operator's configured policy, and each purge that removed anything leaves an `audit.purged` entry behind.

```bash
curl -G http://localhost:8080/v1/audit-log \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -d action=user.blocked \
  -d limit=50
```

## See also

- [models.md](models.md) — full object shapes.
- [errors.md](errors.md) — the complete error catalog, including the
  distinction between per-entry batch codes and top-level HTTP errors,
  and why `403` sometimes stands in for `404`.
