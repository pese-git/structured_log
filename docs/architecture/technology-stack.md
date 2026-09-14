# Technology stack

*Читать на [русском](technology-stack.ru.md).*

Every major dependency choice, the alternative it beat, and why. Each
row traces to a `design.md` decision — read there for the full argument.

## `structured_log_server`

| Choice | Rejected alternative | Why |
|---|---|---|
| `shelf` + `shelf_router` | `dart_frog` | `dart_frog create` imposes its own skeleton/CLI as the primary workflow — breaks with the flat, codegen-free layout of every other package. `dart_frog` is itself built on `shelf`; nothing functional is lost. (decision 1) |
| `drift` over embedded SQLite (`NativeDatabase`) | raw `package:sqlite3` | The **one** deliberate codegen exception in the workspace, by direct user instruction — type-safe, compile-checked queries and built-in schema migration outweigh `build_runner`'s cost for a 7+ table multi-tenant schema. Scoped to this one package; `*.g.dart` is not committed. (decision 2) |
| `LIKE '%term%'` full-text search (via `customSelect`) | FTS5 | Avoids a schema/migration-path complication for functionality outside the agreed MVP scope. Upgrade path noted, not built. (decision 3) |
| One `QueryExecutor`, one isolate, `journal_mode=WAL` | Isolate pool / sharding | `shelf` already serves requests in one isolate by default — a single DB handle needs no extra synchronization. Explicit non-goal to scale beyond it; this is also what makes the [live-stream broadcast](live-streaming.md) an in-process `StreamController` rather than external pub/sub. (decision 4) |
| `dart_jsonwebtoken` (JWT, HS256) | — | Standard JWT library for access-token signing; see [auth.md](auth.md) for the claim shape. |
| `bcrypt` for passwords / SHA-256 for high-entropy secrets | One hash for everything | Two different threat models (offline dictionary attack resistance vs. no need for it) get two different algorithms — see [auth.md](auth.md#password-vs-secret-key-hashing-two-algorithms-for-two-threats). (decision 11) |
| `package:mailer` behind an `EmailSender` interface | Hard-coded SMTP calls | The interface lets an operator swap in a transactional email API without touching the password-reset flow. (decision 24) |

## `structured_log_http`

| Choice | Rejected alternative | Why |
|---|---|---|
| Separate package, `structured_log` as its only dependency | Extend `structured_log` core, or fold into `structured_log_server` | The wire contract evolves with the *server*, not the logging core — coupling it to the independently-versioned, already-published core package isn't justified. It also can't live in `structured_log_server`: an app that only sends logs shouldn't need `shelf`/`drift`/etc. as transitive dependencies. (decision 5) |
| `_SerializedAsyncOutput` pattern (from `AsyncFileOutput`) + batching + retry/backoff | A new queuing design | Reuses an already-proven pattern in the workspace instead of inventing a second one for the same problem shape (serialized delivery, per-step error isolation). |

## `structured_log_admin_client`

| Choice | Rejected alternative | Why |
|---|---|---|
| One Material 3 app, no core/skin split | `structured_log_admin_core` + swappable UI kit | Premature abstraction with a single consumer — the same "don't abstract before a second consumer" principle already applied in `add-structured-log-flutter/design.md`. (decision 18) |
| `dio` | `package:http` | Needs interceptor chaining (token injection, 401→refresh→retry) as a built-in primitive, not hand-rolled. (decision 19) |
| `flutter_secure_storage` | `shared_preferences` | Access/refresh tokens are secrets; `shared_preferences` stores plaintext on most platforms. (decision 20) |
| Own small state layer for the log browser | Reuse `LogViewerController` | Remote, server-filtered, paginated data source is different enough from `LogViewerController`'s local, synchronous, in-memory `LogBuffer` that adapting it would complicate a stable, published API for one new consumer. (decision 21) |

## What's deliberately *not* copied from Keycloak

The auth contract (see [auth.md](auth.md)) matches Keycloak's token
endpoint shape closely enough for an off-the-shelf OAuth2 client to work
against it, but stops well short of a full OIDC/Keycloak surface:

- `client`/`client_id`/`client_secret` and client registration — there's
  exactly one implicit "client" (this API itself), no separate apps to
  register.
- Token introspection endpoint (RFC 7662).
- OIDC UserInfo endpoint.
- Discovery document (`.well-known/openid-configuration`).

None of these serve a consumer this change actually has (decision 10).
Adding them speculatively would be exactly the kind of "abstraction
without a second consumer" the design otherwise avoids everywhere else.

## The one non-negotiable constraint this stack doesn't touch

`structured_log` itself keeps its zero-runtime-dependency rule (only
`meta`) — none of the three new packages add a dependency to it. They're
new packages, not new weight on the existing one.
