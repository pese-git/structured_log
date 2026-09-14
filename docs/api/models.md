# Data models

*Читать на [русском](models.ru.md).*

The JSON object shapes referenced by [http-api.md](http-api.md). These
are not literal quotes from `specs/*.md` — the OpenSpec requirements
deliberately describe *behavior* ("a JSON object identifying the error")
without always pinning down exact field names, so this document commits
to one concrete, consistent shape for all of them, matching the field
names and semantics already fixed in
[design.md](../../openspec/changes/add-structured-log-server/design.md)
and [data-model.md](../architecture/data-model.md) wherever those exist.
If a future revision of `specs/*.md` pins a conflicting shape, that
takes precedence and this document should be updated to match.

## Conventions

- Timestamps are ISO 8601 strings in UTC (`2026-03-05T14:30:00.000Z`).
- Every list endpoint returns `{"items": [...], "next_cursor": "<string, nullable>"}`; pass `next_cursor` back verbatim as the `cursor` query parameter to fetch the next page. `next_cursor: null` means there is no further page.
- A `null` field is present-but-empty; an absent field was never set at all. Requests may omit optional fields entirely.
- Nothing in these shapes ever includes a password hash, a secret-key hash, or a refresh-token hash — those never leave the server in any response.

## User

Returned by `POST /v1/auth/register`, `POST /v1/users`, `PATCH /v1/users/:id`, `GET /v1/users`, `POST /v1/users/:id/block`/`unblock`.

| Field | Type | Notes |
|---|---|---|
| `id` | integer | |
| `username` | string | Unique; the login identifier ([auth.md](../architecture/auth.md)) |
| `display_name` | string \| null | |
| `email` | string \| null | Recovery contact only, not a login identifier |
| `email_verified_at` | string \| null | ISO 8601; `null` blocks `grant_type=password` for this account if `email` is set ([auth.md](../architecture/auth.md#email-verification-mandatory-before-login-not-optional)); always `null` when `email` is `null` |
| `must_change_password` | boolean | `true` whenever an admin set this account's password (creation or `PATCH`); blocks every JWT-authenticated endpoint except a small allowlist until cleared via `POST /v1/auth/change-password` ([auth.md](../architecture/auth.md#patch-v1usersid-and-the-mandatory-temporary-password)); always `false` for self-registered accounts |
| `is_active` | boolean | `false` while blocked ([rbac-and-lifecycle.md](../architecture/rbac-and-lifecycle.md)) |
| `deleted_at` | string \| null | ISO 8601; set once, never cleared |
| `is_primary_admin` | boolean | `true` on at most one user, ever |
| `created_at` | string | ISO 8601 |

```json
{
  "id": 42,
  "username": "alice",
  "display_name": "Alice Chen",
  "email": "alice@example.com",
  "email_verified_at": null,
  "must_change_password": false,
  "is_active": true,
  "deleted_at": null,
  "is_primary_admin": false,
  "created_at": "2026-01-10T09:00:00.000Z"
}
```

## Group

| Field | Type | Notes |
|---|---|---|
| `id` | integer | |
| `name` | string | |
| `created_at` | string | ISO 8601 |

## Team

| Field | Type | Notes |
|---|---|---|
| `id` | integer | |
| `group_id` | integer | Exactly one owning group |
| `name` | string | |
| `created_at` | string | ISO 8601 |

## Project

Returned by `POST /v1/groups/:groupId/projects`, `PATCH /v1/projects/:id`, `GET /v1/projects/:id`, `POST /v1/projects/:id/block`/`unblock`. `GET /v1/projects/:id` additionally includes `entry_count`/`total_bytes` (decision 22, [quotas-and-audit.md](../architecture/quotas-and-audit.md)); the other endpoints above omit them (not maintained/queried outside the single-project read path).

| Field | Type | Notes |
|---|---|---|
| `id` | integer | |
| `group_id` | integer | |
| `name` | string | |
| `retention_days` | integer | Mandatory |
| `max_entries` | integer \| null | `null` = unlimited |
| `max_bytes` | integer \| null | `null` = unlimited |
| `is_blocked` | boolean | |
| `created_at` | string | ISO 8601 |
| `entry_count` | integer | **`GET /v1/projects/:id` only** |
| `total_bytes` | integer | **`GET /v1/projects/:id` only** |

```json
{
  "id": 7,
  "group_id": 3,
  "name": "checkout-service",
  "retention_days": 30,
  "max_entries": 1000000,
  "max_bytes": null,
  "is_blocked": false,
  "created_at": "2026-01-12T11:00:00.000Z",
  "entry_count": 842317,
  "total_bytes": 512048221
}
```

## ProjectSecretKey

Metadata never includes the plaintext key value, **except** the
response to `POST /v1/projects/:id/secret-keys`, which carries `secret`
exactly once — it is not retrievable afterward by any endpoint.

| Field | Type | Notes |
|---|---|---|
| `id` | integer | |
| `project_id` | integer | |
| `label` | string \| null | |
| `created_at` | string | ISO 8601 |
| `revoked_at` | string \| null | |
| `secret` | string | **Only in the create response** — the plaintext value, shown once |

## RoleAssignment

| Field | Type | Notes |
|---|---|---|
| `id` | integer | |
| `subject_type` | `"user"` \| `"team"` | |
| `subject_id` | integer | |
| `role` | `"admin"` \| `"owner"` \| `"user"` | |
| `scope_type` | `"global"` \| `"group"` \| `"project"` | |
| `scope_id` | integer \| null | `null` iff `scope_type: "global"` |
| `created_at` | string | ISO 8601 |

## LogEntry

Returned by `GET /v1/logs` and streamed by `GET /v1/logs/stream`
([live-streaming.md](../architecture/live-streaming.md)). There is no
separate "context wrapper" — the response is the exact JSON object the
client sent to `POST /v1/logs` (see below), merged with three
server-assigned fields, preserving whatever custom keys it contained
(`log-server-storage`'s "full original content" guarantee, see
[data-model.md](../architecture/data-model.md)).

| Field | Type | Notes |
|---|---|---|
| `id` | integer | Server-assigned; keyset-pagination cursor |
| `project_id` | integer | Server-assigned, from the secret key that authenticated ingestion |
| `received_at` | string | Server-assigned; ISO 8601, independent of client `timestamp` |
| `event` | string | As submitted |
| `level` | string | As submitted — one of `debug`/`info`/`warning`/`error`/`critical` |
| `timestamp` | string | As submitted, ISO 8601 |
| `category` | string \| null | As submitted, if present |
| `logger` | string \| null | As submitted, if present |
| `session_id`, `request_id`, `connection_generation`, `tool_call_id`, `message_id`, `operation_id` | string \| null | Correlation fields, as submitted, if present |
| *(any other key)* | any | Whatever custom `context` fields the client submitted, unchanged |

```json
{
  "id": 918273,
  "project_id": 7,
  "received_at": "2026-03-05T14:30:00.412Z",
  "event": "payment_failed",
  "level": "error",
  "timestamp": "2026-03-05T14:29:59.981Z",
  "category": "checkout",
  "logger": "payment.gateway",
  "session_id": "sess_abc123",
  "request_id": "req_xyz789",
  "connection_generation": null,
  "tool_call_id": null,
  "message_id": null,
  "operation_id": null,
  "order_id": "ord_44821",
  "gateway_response_code": "card_declined"
}
```

(`order_id`/`gateway_response_code` above are arbitrary custom fields —
not part of the fixed schema, preserved exactly as sent.)

## AuditLogEntry

Returned by `GET /v1/audit-log` ([quotas-and-audit.md](../architecture/quotas-and-audit.md)).

| Field | Type | Notes |
|---|---|---|
| `id` | integer | |
| `actor_user_id` | integer \| null | `null` for events genuinely without an authenticated caller — in practice `auth.login_failed`/`auth.throttled` under a username that matches no account (see [quotas-and-audit.md](../architecture/quotas-and-audit.md)) |
| `action` | string | One of the closed set — see [quotas-and-audit.md](../architecture/quotas-and-audit.md) |
| `target_type` | string | e.g. `"user"`, `"project"`, `"role_assignment"` |
| `target_id` | integer \| null | |
| `metadata` | object | Shape depends on `action` — see examples below |
| `created_at` | string | ISO 8601 |

`metadata` examples by action:

```json
// action: "project.quota_updated"
{"before": {"retention_days": 30, "max_entries": null}, "after": {"retention_days": 30, "max_entries": 1000000}}

// action: "role_assignment.created"
{"role": "owner", "scope_type": "group", "scope_id": 3, "subject_type": "user", "subject_id": 42}

// action: "user.blocked"
{}

// action: "auth.login_succeeded"
{"client_ip": "203.0.113.7", "user_agent": "structured_log_admin_client/0.1.0"}

// action: "auth.login_failed" — known account
{"reason": "invalid_password", "client_ip": "203.0.113.7", "user_agent": "..."}

// action: "auth.login_failed" — no such account (actor_user_id is null,
// and the submitted username is deliberately NOT stored)
{"unknown_user": true, "client_ip": "203.0.113.7", "user_agent": "..."}

// action: "auth.throttled" — written once per episode, not per rejected request
{"key_kind": "subject", "path": "/v1/auth/token", "client_ip": "203.0.113.7"}
```

## Token response

Returned by `POST /v1/auth/token` (RFC 6749 §5.1 field names —
[auth.md](../architecture/auth.md)).

| Field | Type | Notes |
|---|---|---|
| `access_token` | string | JWT, short-lived |
| `refresh_token` | string | Opaque, long-lived |
| `token_type` | string | Always `"Bearer"` |
| `expires_in` | integer | Seconds until `access_token` expires |
| `refresh_expires_in` | integer | Seconds until `refresh_token` expires |

## Access-token claims (decoded JWT payload)

Not a response body — the payload of `access_token` once decoded, for
reference when debugging.

| Claim | Type | Notes |
|---|---|---|
| `iss` | string | Configured server issuer identifier |
| `sub` | string | `User.id` |
| `iat` / `exp` | integer | Unix timestamps |
| `jti` | string | Unique token id |
| `preferred_username` | string | |
| `tv` | integer | `User.token_version` snapshot at issuance — [auth.md](../architecture/auth.md#token_version-how-a-snapshot-in-a-jwt-stays-revocable) |
| `roles` | array of `{role, scope_type, scope_id}` | Effective-rights snapshot at issuance |

## Ingestion response

Returned by `POST /v1/logs`, HTTP `202` — **always**, even if every
entry in the batch was rejected; the request itself was accepted and
processed entry-by-entry, so a `4xx`/`5xx` would misrepresent what
happened (see [errors.md](errors.md#partial-batch-acceptance-is-not-an-error)).

| Field | Type | Notes |
|---|---|---|
| `accepted` | integer | Count of entries stored |
| `rejected` | array of `{index, error, message}` | `index` is the entry's position in the submitted array (0-based) |

```json
{
  "accepted": 8,
  "rejected": [
    {"index": 3, "error": "validation_error", "message": "level: must be one of debug, info, warning, error, critical"},
    {"index": 7, "error": "quota_exceeded", "message": "project max_entries limit reached"}
  ]
}
```

## Error envelope

Two shapes coexist in this API, both documented in full in
[errors.md](errors.md) — this is a pointer, not a duplicate:

- The general JSON envelope (`log-server-api`), used by everything except the token endpoint.
- The RFC 6749 §5.2 shape, used **only** by `POST`/`DELETE /v1/auth/token`.
