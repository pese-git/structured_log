# Technology stack

*Читать на [русском](technology-stack.ru.md).*

Every major dependency choice, the alternative it beat, and why. Each
row traces to a `design.md` decision — read there for the full argument.

## `structured_log_server`

| Choice | Rejected alternative | Why |
|---|---|---|
| `shelf` + `shelf_router` | `dart_frog` | `dart_frog create` imposes its own skeleton/CLI as the primary workflow — breaks with the flat, codegen-free layout of every other package. `dart_frog` is itself built on `shelf`; nothing functional is lost. (decision 1) |
| `shelf_router_generator` for the route table | Hand-written `Router` cascade | The route was written twice — once in `buildHandler`, once in the handler's doc comment — and path-parameter names were checked only at runtime (a typo answered 404 forever). Annotating handlers makes the path single-sourced and the parameter arity a build error. Only viable *after* `unify-server-auth`: the generator cannot annotate middleware, so while auth wrappers sat on each route, adopting it would have pushed them into handler bodies. |
| `drift` over embedded SQLite (`NativeDatabase`) | raw `package:sqlite3` | The first deliberate codegen exception in the workspace, by direct user instruction — type-safe, compile-checked queries and built-in schema migration outweigh `build_runner`'s cost for a 7+ table multi-tenant schema. Scoped to this one package; `*.g.dart` is not committed. (decision 2, extended by decision 34 below) |
| `LIKE '%term%'` full-text search (via `customSelect`) | FTS5 | Avoids a schema/migration-path complication for functionality outside the agreed MVP scope. Upgrade path noted, not built. (decision 3) |
| One `QueryExecutor`, one isolate, `journal_mode=WAL` | Isolate pool / sharding | `shelf` already serves requests in one isolate by default — a single DB handle needs no extra synchronization. Explicit non-goal to scale beyond it; this is also what makes the [live-stream broadcast](live-streaming.md) an in-process `StreamController` rather than external pub/sub. (decision 4) |
| `dart_jsonwebtoken` (JWT, HS256) | — | Standard JWT library for access-token signing; see [auth.md](auth.md) for the claim shape. |
| `bcrypt` for passwords / SHA-256 for high-entropy secrets | One hash for everything | Two different threat models (offline dictionary attack resistance vs. no need for it) get two different algorithms — see [auth.md](auth.md#password-vs-secret-key-hashing-two-algorithms-for-two-threats). (decision 11) |
| `package:mailer` behind an `EmailSender` interface | Hard-coded SMTP calls | The interface lets an operator swap in a transactional email API without touching the password-reset flow. (decision 24) |
| `structured_log` for the server's own diagnostics | `package:logging`, or `print()` | The workspace exists for this library — picking someone else's for its own service would say either that it isn't ready for real use or that its author doesn't use it. Also the first non-trivial consumer of `BoundLogger`/`AsyncRotatingFileOutput` (decision 48) |
| `fpdart` (`Either`/`Option`) for expected failures | Exceptions everywhere (the rest of the workspace's style) | Validation errors, RBAC denials, quota limits are part of the contract a caller must handle explicitly, not exceptional control flow; genuine bugs still throw. (decision 33) |
| `freezed` + `json_serializable` for immutable models/unions | Hand-written value classes | Same `build_runner` run already needed for `drift`; avoids hand-maintained `==`/`copyWith` drifting out of sync as the model count grows. (decision 34) |

## `structured_log_http`

| Choice | Rejected alternative | Why |
|---|---|---|
| Separate package, `structured_log` as its only dependency | Extend `structured_log` core, or fold into `structured_log_server` | The wire contract evolves with the *server*, not the logging core — coupling it to the independently-versioned, already-published core package isn't justified. It also can't live in `structured_log_server`: an app that only sends logs shouldn't need `shelf`/`drift`/etc. as transitive dependencies. (decision 5) |
| `_SerializedAsyncOutput` pattern (from `AsyncFileOutput`) + batching + retry/backoff | A new queuing design | Reuses an already-proven pattern in the workspace instead of inventing a second one for the same problem shape (serialized delivery, per-step error isolation). |

`structured_log_http` is not part of the decisions 32–38 tech-stack expansion below — it stays a small, dependency-free client package, unaffected by `structured_log_server`'s or `structured_log_admin_client`'s internal choices.

## `structured_log_admin_client`

| Choice | Rejected alternative | Why |
|---|---|---|
| One app, no core/skin split | `structured_log_admin_core` + swappable UI kit | Premature abstraction with a single consumer — the same "don't abstract before a second consumer" principle already applied in `add-structured-log-flutter/design.md`. (decision 18) |
| `fluent_ui`, not Material 3 | Material 3 (the original decision 18) | Revises decision 18's UI-kit pick specifically (the "no core/skin split" part is unrelated and stands). Screens are pre-designed externally (Claude Design); implementation follows those mockups where they exist. Does **not** mean reusing `structured_log_fluent`'s widgets — decision 21 (different data source) still applies; the shared design system is a visual coincidence, not shared code. (decision 38) |
| `dio` + `retrofit` for typed endpoints | `package:http`, or hand-written `dio` calls everywhere | `dio` needs interceptor chaining (token injection, 401→refresh→retry) as a built-in primitive (decision 19); `retrofit` removes hand-written serialization boilerplate for the ~15 JSON endpoints. `GET /v1/logs/stream` is the one deliberate exception — hand-written directly on the same `dio` instance, because a long-lived streamed body with custom SSE-frame parsing doesn't fit retrofit's one-call/one-typed-response model. (decisions 19, 37) |
| `flutter_secure_storage` | `shared_preferences` | Access/refresh tokens are secrets; `shared_preferences` stores plaintext on most platforms. (decision 20) |
| `flutter_bloc` (`Bloc`/`Cubit`) for state | `riverpod`/`provider`/an unspecified `ChangeNotifier`-style controller | Concretizes the "own small state layer" for the log browser (decision 21/30) as an explicit state machine — the log feed's `Following`/`ScrolledUp`/`Paused` states and their transitions map directly onto a `Bloc`. Used the same way for every other screen. (decision 36) |
| `fpdart` (`Either`/`Option`) for expected failures | Exceptions everywhere | Same principle as the server (see above): network errors, `invalid_grant`, permission denials flow as `Either` from `infrastructure`/`application` up to `presentation`. (decision 33) |
| `freezed` + `json_serializable` for models/DTOs/Bloc states | Hand-written value classes | Pairs naturally with `fpdart`'s `Either<Failure, T>` — both sides are typically `freezed` classes. (decision 34) |
| `structured_log` for the app's own diagnostics | `package:logging`, `debugPrint` | Same dogfooding argument as the server. Revises decision 19's blanket "no dependency on `structured_log`" — a general-purpose logging library carries no part of the API contract, so the no-shared-contract-code rule is untouched (decision 48) |
| `cherrypick` for dependency injection | `get_it`/`provider`/manual constructor wiring | Same author's own DI library — already the namesake for this workspace's `emb/` layout convention (`AGENTS.md`), now used directly as a dependency for the first time. (decision 35) |

## `structured_log_admin_ui`

| Choice | Rejected alternative | Why |
|---|---|---|
| Separate package, `flutter` sdk + `fluent_ui` only | A `lib/shared/widgets/` folder inside `structured_log_admin_client` | A folder is a convention a `Bloc` import can violate by accident; a separate package with no dependency on `fpdart`/`freezed`/`cherrypick`/`flutter_bloc`/`dio`/`retrofit`/`structured_log_admin_client` makes that a compile error instead. (decision 39) |
| Only `atoms`/`molecules`/`organisms` (three tiers) | The classic five-tier Atomic Design (+ `templates`/`pages`) | `templates`/`pages` assemble organisms with real data — by definition tied to one feature's business logic, which is exactly what this package must not contain. They stay in `structured_log_admin_client`'s own `presentation` layer instead. (decision 39) |
| `LogLevelBadge` owns its own color mapping | Import `logLevelColor()` from `structured_log_material`/`fluent` | Decision 21 already rules out sharing code with the viewer packages; this follows the same duplication precedent those two packages already set between each other. |

See [admin-client.md](admin-client.md#the-component-library-structured_log_admin_ui)
for the tier boundaries and an illustrated component tree.

## Architecture pattern

Both new packages are organized **feature-first** (`auth`, `users`,
`projects`, `logs`, ...) rather than by technical file type across the
whole package — decision 32. Inside each feature, the layering differs
because only one of the two packages has a UI to separate from domain
logic:

```mermaid
flowchart TB
    subgraph Server["structured_log_server (per feature)"]
        SD["domain"] --- SDa["data"] --- SH["http"]
    end
    subgraph Client["structured_log_admin_client (per feature)"]
        CD["domain"] --- CA["application"] --- CI["infrastructure"] --- CP["presentation\n(Bloc/Cubit + widgets)"]
    end
```

- **Server: a simpler layered split, not full Clean Architecture** — no
  presentation layer exists in a headless HTTP API, so a four-layer
  split would be structure for its own sake.
- **Client: full Clean Architecture** (`domain`/`application`/`infrastructure`/`presentation`)
  — the client has a real presentation layer (`flutter_bloc` +
  `fluent_ui` widgets), so separating it from domain/business logic pays
  for itself in testability (domain logic tested without Flutter,
  `infrastructure` swapped for a fake in tests).
- **Shared code** (the server's multi-tenant storage tables; the
  client's `ApiClient`/token storage/DI wiring) lives outside any one
  feature, in a `shared`/`common` layer used by several features at
  once.
- **Exact folder names are left to implementation** — `tasks.md`
  describes work by capability, not by a fixed file tree, so this
  doesn't get pinned down speculatively ahead of writing real code (see
  `design.md`'s Open Questions).

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
