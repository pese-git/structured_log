# HTTP API reference

*Читать на [русском](http-api.ru.md).*

A compact index of every `structured_log_server` endpoint, grouped by
capability. This is a reading aid, not the contract itself — for exact
request/response shapes and every scenario, follow the spec link in each
section. Field-level detail belongs in `specs/`, not here; this table
exists so you don't have to open eight files to see the whole surface at
once.

Error responses (outside the two exceptions noted below) are a JSON
object identifying the error type/reason — see
[specs/log-server-api/spec.md](../../openspec/changes/add-structured-log-server/specs/log-server-api/spec.md)'s
"Ошибки возвращаются в структурированном JSON-формате" requirement.

## Log ingestion, query, and live stream (`log-server-api`, `log-server-live-stream`)

Spec:
[specs/log-server-api/spec.md](../../openspec/changes/add-structured-log-server/specs/log-server-api/spec.md),
[specs/log-server-live-stream/spec.md](../../openspec/changes/add-structured-log-server/specs/log-server-live-stream/spec.md).

| Method & path | Auth | Notes |
|---|---|---|
| `POST /v1/logs` | Project secret key | Batch insert; partial acceptance on validation/quota failure; `403 project_blocked` if the project is blocked |
| `GET /v1/logs` | Access-JWT | Requires exactly one of `project_id`/`group_id`; filters: `level`/`category`/`logger`/`from`/`to`/correlation fields/`q`/`context.*`; keyset pagination by `id`, newest-first by default (decision 31) |
| `GET /v1/logs/stream` | Access-JWT | Same scope/filters as `GET /v1/logs`, plus `since_id`; `Content-Type: text/event-stream`; see [live-streaming.md](../architecture/live-streaming.md) |
| `GET /healthz` | None | 200 once storage is initialized and ready |

## Authentication and password recovery (`log-server-auth`, `log-server-password-reset`)

Spec:
[specs/log-server-auth/spec.md](../../openspec/changes/add-structured-log-server/specs/log-server-auth/spec.md),
[specs/log-server-password-reset/spec.md](../../openspec/changes/add-structured-log-server/specs/log-server-password-reset/spec.md).
See [auth.md](../architecture/auth.md) for the full picture.

| Method & path | Auth | Notes |
|---|---|---|
| `POST /v1/auth/register` | None | Form: `username`/`password`/`email` (required)/`display_name`; only if `registrationEnabled`; creates a user with no `RoleAssignment` |
| `POST /v1/auth/token` | None | Form-encoded, RFC 6749; `grant_type=password` or `grant_type=refresh_token`; response/error shapes follow RFC 6749 §5.1/§5.2, **not** the JSON error envelope used elsewhere |
| `DELETE /v1/auth/token` | None (bearer refresh token in body) | Form-encoded, RFC 7009; always `200`, empty body, valid token or not |
| `POST /v1/auth/password-reset` | None | JSON `{email}`; always `202`, same body, regardless of whether the email exists |
| `POST /v1/auth/password-reset/confirm` | None (bearer reset token in body) | JSON `{token, new_password}`; `400 invalid_token` if expired/used/unknown |
| `DELETE /v1/users/me` | Access-JWT + password in body | Self-delete; `403 cannot_delete_primary_admin` / `409 sole_group_owner` possible |

## Users, groups, teams, roles (`log-server-rbac`)

Spec:
[specs/log-server-rbac/spec.md](../../openspec/changes/add-structured-log-server/specs/log-server-rbac/spec.md).
See [rbac-and-lifecycle.md](../architecture/rbac-and-lifecycle.md).

| Method & path | Role required | Notes |
|---|---|---|
| `POST /v1/users` | `admin` | Create a user; `email` optional here (unlike self-registration) |
| `GET /v1/users` | `admin` | List users |
| `POST /v1/users/:id/block` | `admin` | Revokes all refresh tokens too |
| `POST /v1/users/:id/unblock` | `admin` | `400` if the target is deleted |
| `DELETE /v1/users/:id` | `admin` | `400` if `:id == self`; `403 cannot_delete_primary_admin` / `409 sole_group_owner` possible |
| `POST /v1/groups` | `admin` | |
| `GET /v1/groups` | Any authenticated user | Scoped to visible groups |
| `POST /v1/groups/:groupId/teams` | `owner` of the group, or `admin` | |
| `POST /v1/teams/:teamId/members` | `owner`/`admin` | Bumps `token_version` for all current members |
| `DELETE /v1/teams/:teamId/members/:userId` | `owner`/`admin` | Same |
| `POST /v1/role-assignments` | `admin` (any grant) or `owner` (`owner`/`user` within their own group) | |
| `DELETE /v1/role-assignments/:id` | Same rule as above | |

## Projects and quotas (`log-server-rbac`, `log-server-quotas`)

Spec:
[specs/log-server-quotas/spec.md](../../openspec/changes/add-structured-log-server/specs/log-server-quotas/spec.md).
See [quotas-and-audit.md](../architecture/quotas-and-audit.md).

| Method & path | Role required | Notes |
|---|---|---|
| `POST /v1/groups/:groupId/projects` | `owner` of the group, or `admin` | `retention_days` mandatory |
| `PATCH /v1/projects/:id` | `owner`/`admin` | Quota edits |
| `GET /v1/projects/:id` | `owner`/`user` with access/`admin` | Includes `entry_count`/`total_bytes` alongside the configured quota |
| `POST /v1/projects/:id/block` | `admin` only (not `owner`) | Halts both ingestion and direct query |
| `POST /v1/projects/:id/unblock` | `admin` only | |
| `POST /v1/projects/:id/secret-keys` | `owner`/`admin` | Plaintext key shown once, in the create response only |
| `GET /v1/projects/:id/secret-keys` | `owner`/`admin` | Metadata only |
| `DELETE /v1/projects/:id/secret-keys/:keyId` | `owner`/`admin` | Irreversible |

## Audit log (`log-server-audit`)

Spec:
[specs/log-server-audit/spec.md](../../openspec/changes/add-structured-log-server/specs/log-server-audit/spec.md).
See [quotas-and-audit.md](../architecture/quotas-and-audit.md#audit-log-log-server-audit).

| Method & path | Role required | Notes |
|---|---|---|
| `GET /v1/audit-log` | `admin` only (not `owner`) | Filters: `actor_user_id`/`action`/`target_type`/`target_id`/`from`/`to`; keyset pagination |

## Two intentional inconsistencies

- `POST`/`DELETE /v1/auth/token` and `POST /v1/auth/password-reset*` use
  form-encoded bodies and RFC-shaped errors instead of this API's usual
  JSON envelope — see [auth.md](../architecture/auth.md) for why this is
  documented as deliberate, not an oversight.
- `507 Insufficient Storage`, not `413`, signals a quota rejection on
  `POST /v1/logs` — `413` is reserved for exceeding the HTTP body size
  limit. See [quotas-and-audit.md](../architecture/quotas-and-audit.md).
