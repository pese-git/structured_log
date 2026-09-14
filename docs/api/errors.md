# Errors

*Читать на [русском](errors.ru.md).*

Every error `structured_log_server` can return, in one place, so a
client can handle them exhaustively instead of discovering codes
endpoint by endpoint. Object shapes referenced below are in
[models.md](models.md).

## Two error envelope shapes

**General envelope** — every endpoint except the token endpoint (below):

```json
{
  "error": "<machine-readable code, e.g. \"validation_error\">",
  "message": "<human-readable description>",
  "details": { "...": "optional, error-specific — see individual codes below" }
}
```

**Token endpoint only** (`POST`/`DELETE /v1/auth/token`) — RFC 6749 §5.2
shape, a deliberate, isolated exception for compatibility with
off-the-shelf OAuth2 clients ([auth.md](../architecture/auth.md)):

```json
{
  "error": "invalid_grant",
  "error_description": "<human-readable description>"
}
```

Nothing else in this API uses the `error_description` field name, and
the token endpoint never uses `message`/`details` — the two shapes don't
mix on one response.

## Full catalog

| HTTP status | `error` code | Envelope | Where it can occur | Meaning |
|---|---|---|---|---|
| 400 | `invalid_request` | general | Any JSON endpoint | Malformed JSON body, or a required field is missing/wrong type |
| 400 | `invalid_request` | RFC | `DELETE /v1/auth/token` | `refresh_token` field missing from the form body |
| 400 | `invalid_request` | RFC | `POST /v1/auth/token` | Required field missing for the given `grant_type` |
| 400 | `unsupported_grant_type` | RFC | `POST /v1/auth/token` | `grant_type` is neither `password` nor `refresh_token` |
| 400 | `invalid_grant` | RFC | `POST /v1/auth/token` | Wrong `username`/`password`; or `refresh_token` unknown/expired/revoked; or the user is blocked (`grant_type=refresh_token`) |
| 400 | `invalid_token` | general | `POST /v1/auth/password-reset/confirm` | Reset token unknown, expired, or already used |
| 400 | `self_deletion_requires_me` | general | `DELETE /v1/users/:id` | `:id` equals the caller's own id — self-deletion must go through `DELETE /v1/users/me` |
| 401 | `unauthorized` | general | Any JWT-protected endpoint | `Authorization` header missing/malformed; JWT signature/expiry invalid; or claim `tv` no longer matches `User.token_version` ([auth.md](../architecture/auth.md#token_version-how-a-snapshot-in-a-jwt-stays-revocable)) |
| 401 | `unauthorized` | general | `POST /v1/logs` | Project secret key missing, unknown, or `revoked_at` is set |
| 401 | `invalid_grant` | general | `DELETE /v1/users/me` | Current-password confirmation is wrong |
| 403 | `forbidden` | general | Management/query endpoints | Caller's effective roles don't cover the requested scope/action ([rbac-and-lifecycle.md](../architecture/rbac-and-lifecycle.md)) |
| 403 | `project_blocked` | general | `POST /v1/logs`, `GET /v1/logs?project_id=`, `GET /v1/logs/stream?project_id=` | Target project has `is_blocked = true`; overrides normal authorization rather than adding to it |
| 403 | `cannot_delete_primary_admin` | general | `DELETE /v1/users/me`, `DELETE /v1/users/:id` | Target has `is_primary_admin = true` — see [rbac-and-lifecycle.md](../architecture/rbac-and-lifecycle.md) |
| 404 | `not_found` | general | Any `:id`-addressed endpoint; `GET /v1/logs`/`stream` with an unknown `project_id`/`group_id` | Resource doesn't exist (distinguished from 403 only when existence itself isn't sensitive — see note below) |
| 409 | `username_taken` | general | `POST /v1/auth/register`, `POST /v1/users` | `username` already belongs to another row (deleted accounts still reserve it — [rbac-and-lifecycle.md](../architecture/rbac-and-lifecycle.md)) |
| 409 | `email_taken` | general | `POST /v1/auth/register`, `POST /v1/users` | `email` already belongs to another row, same reservation rule |
| 409 | `sole_group_owner` | general | `DELETE /v1/users/me`, `DELETE /v1/users/:id` | Target is the sole `owner` of one or more groups; `details.blocking_groups` lists them ([rbac-and-lifecycle.md](../architecture/rbac-and-lifecycle.md)) |
| 409 | `deleted_account` | general | `POST /v1/users/:id/unblock` | Target has `deleted_at` set — `unblock` never reactivates a deleted account |
| 413 | `payload_too_large` | general | `POST /v1/logs` | Request body exceeds the configured size limit; no entries are stored |
| 500 | `internal_error` | general | Any | Unexpected server-side failure; the response never includes a stack trace or other internal detail |
| 507 | `quota_exceeded` | general | `POST /v1/logs` | Only appears *inside* a `202` ingestion response's `rejected[]` array (see below), never as the top-level HTTP status of the response |

Per-entry batch codes (`validation_error`, `quota_exceeded`) are
documented separately below — they never appear as a top-level HTTP
error, only inside a successful `202` response body.

## Partial batch acceptance is not an error

`POST /v1/logs` is the one endpoint where "some of this request failed"
is not expressed as an HTTP error at all. The request itself always
succeeds with `202` if it's well-formed and authenticated — individual
entries are accepted or rejected independently, reported in the
response body ([models.md](models.md#ingestion-response)):

| `rejected[].error` | Meaning |
|---|---|
| `validation_error` | The entry is malformed — e.g. missing `level`, or `level` isn't one of the recognized values |
| `quota_exceeded` | Accepting this entry would exceed the project's `max_entries`/`max_bytes` ([quotas-and-audit.md](../architecture/quotas-and-audit.md)) |

Even a batch where every single entry is rejected still returns `202`
with `"accepted": 0` — the request was processed, just with nothing
accepted. The only ways `POST /v1/logs` returns a top-level error
instead are: bad/missing/revoked secret key (`401`), the project is
blocked (`403 project_blocked`, entire batch, no entries evaluated), or
the body exceeds the size limit (`413`, entire batch, no entries
evaluated).

## 403 vs. 404: when existence is itself sensitive

Most `:id` lookups return `404 not_found` for both "doesn't exist" and,
where relevant, "exists but you have no rights to it" — distinguishing
the two would leak whether a resource exists to someone with no
business knowing. The one deliberate exception is `GET /v1/logs`/`GET
/v1/logs/stream`'s scope check: a `project_id`/`group_id` the caller
has literally no grant for is `403 forbidden`, not `404` — per
`log-server-api`'s own scenarios, existence of a project/group id is not
treated as sensitive the way, say, another user's private data would be
(project/group ids are visible to more people than have query rights on
them, e.g. anyone in the same organization).

## `details` by error code

Most codes carry no `details` (the top-level `message` is enough).
Codes that do:

| Code | `details` shape |
|---|---|
| `sole_group_owner` | `{"blocking_groups": [{"id": 3, "name": "checkout-team"}, ...]}` |
| `invalid_request` | `{"field": "level", "reason": "required"}` (when the failing field is unambiguous) |

## Errors that never reach the client as HTTP responses

`GET /v1/logs/stream`'s terminal SSE event (`event: end`, `data:
{"reason": "token_revoked" | "project_blocked"}`) is not an HTTP error —
the connection already answered `200` before streaming began, so a
revoked grant or a mid-stream project block is signaled through the
stream's content instead. See
[live-streaming.md](../architecture/live-streaming.md#re-validating-a-long-lived-connection).
Treat it the same as a `401`/`403` for reconnect purposes.
