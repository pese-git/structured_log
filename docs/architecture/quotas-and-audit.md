# Quotas and audit log

*Читать на [русском](quotas-and-audit.ru.md).*

Two independent capabilities that happen to share a theme — keeping the
system bounded and inspectable. Normative requirements:
[specs/log-server-quotas/spec.md](../../openspec/changes/add-structured-log-server/specs/log-server-quotas/spec.md),
[specs/log-server-audit/spec.md](../../openspec/changes/add-structured-log-server/specs/log-server-audit/spec.md).

## Quotas (`log-server-quotas`)

Every `Project` has `retention_days` (mandatory — no project can opt out
of a retention policy) and optionally `max_entries`/`max_bytes`
(`null` = unlimited on that dimension). Decision 13.

```mermaid
flowchart TD
    subgraph Ingest["POST /v1/logs"]
        A["batch arrives"] --> B{"per entry:\nwould accepting it\nexceed max_entries/max_bytes?"}
        B -->|no| C["insert, ProjectUsage += 1 entry / N bytes"]
        B -->|yes| D["reject this entry only\nquota_exceeded, 507"]
    end
    subgraph Purge["periodic purge job"]
        E["timer tick\n(configurable interval)"] --> F["delete log_entries older\nthan retention_days, per project"]
        F --> G["ProjectUsage -= deleted\nentries / bytes"]
    end
```

- **Usage is a maintained counter, not a live aggregate.** `ProjectUsage
  (project_id, entry_count, total_bytes)` is updated atomically in the
  same transaction as the batch insert and the purge job — so checking
  "are we over quota" is a cheap point-lookup, never a `COUNT(*)`/`SUM()`
  over the whole `log_entries` table.
- **`max_entries`/`max_bytes` enforcement rejects individual entries,
  not the whole batch** — the same partial-acceptance mechanism already
  used for validation errors (see
  [api/http-api.md](../api/http-api.md)'s ingestion entry).
- **`retention_days` enforcement is a periodic purge, not an on-write
  check** — this is deliberately *eventual*, not hard real-time: under
  very high load the purge job can lag briefly behind the nominal
  retention window. Documented as an accepted MVP trade-off, not a bug.
- **`507 Insufficient Storage`**, not `413`, is used for quota rejection
  — `413` is reserved in this API for exceeding the HTTP body size
  limit; `507`'s literal RFC semantics ("the server is unable to store
  the representation") fit the quota case more precisely.
- `GET /v1/projects/:id` returns current usage alongside the configured
  quota (`entry_count`/`total_bytes` next to `max_entries`/`max_bytes`)
  — a small addition made specifically so
  `structured_log_admin_client` can render "used / limit" without a
  second, internal-only endpoint.

## Audit log (`log-server-audit`)

Every mutating management operation — not log ingestion or querying —
is recorded, admin-readable only.

```mermaid
flowchart LR
    Op["Mutating operation\n(e.g. role grant, block,\nquota change, key revoke)"] --> Tx{"Same DB transaction"}
    Tx --> M["Apply the mutation"]
    Tx --> A["Insert into\naudit_log_entries"]
    Tx --> Commit["Commit"]
    Tx -.->|rollback either way| Rollback["Neither the mutation\nnor the audit row persists"]
```

- **One transaction covers both the mutation and its audit row** — if
  the operation itself rolls back (e.g. a delete rejected by the
  sole-group-owner check, see
  [rbac-and-lifecycle.md](rbac-and-lifecycle.md)), no audit row is left
  behind claiming it happened.
- **A closed set of `action` values**, not free text: `user.created`,
  `user.blocked`, `user.unblocked`, `user.deleted`, `group.created`,
  `team.created`, `team.member_added`, `team.member_removed`,
  `project.created`, `project.quota_updated`, `project.blocked`,
  `project.unblocked`, `secret_key.created`, `secret_key.revoked`,
  `role_assignment.created`, `role_assignment.revoked`,
  `password.reset_confirmed`, `email.verified`, `user.updated`,
  `password.changed`, `auth.login_succeeded`, `auth.login_failed`,
  `auth.logged_out`, `auth.throttled`, `audit.purged`.
- **Authentication events are in the set, session refresh is not**
  (decision 44). A successful `grant_type=password`, a rejected one, an
  explicit `DELETE /v1/auth/token`, and the rate limiter tripping
  ([auth.md](auth.md#rate-limiting-throttling-without-lockout)) are all
  recorded; `grant_type=refresh_token` is not — it continues an access
  decision already made and recorded, and at roughly one event per
  session per 15 minutes it would outnumber everything else combined.
  These four — and `audit.purged` — are the only actions exempt from the
  same-transaction rule above: a rejected login, and a purge pass, have
  no resource mutation to share a transaction with.
- **What authentication events never store**: the submitted password, in
  any form, and the submitted `username` when it matches no account. For
  an unknown account the row carries `actor_user_id: null` and
  `{"unknown_user": true}` — nothing more. The reason isn't volume: a
  password regularly lands in the username field (mistyped, or a
  password-manager paste that slipped a field), and storing "the unknown
  username" would quietly turn the admin audit view into a collection of
  other people's passwords in the clear. For a known account there's
  nothing to store anyway — `actor_user_id` already identifies them.
  `metadata` does carry `client_ip`, `user_agent`, and a `reason`
  (`invalid_password` / `unknown_user` / `email_not_verified` /
  `blocked` / `deleted`).
- **`auth.throttled` is written once per episode**, at the moment a
  bucket empties — not once per rejected request. Otherwise the audit
  log would amplify the very attack it records: a thousand rejected
  requests would mean a thousand inserts, making a rejected request more
  expensive for the server than an accepted one.
- **Explicitly excluded**: `POST`/`GET /v1/logs` and `GET
  /v1/logs/stream` (high-frequency business data, not an administrative
  action over the service's own resources — see
  [live-streaming.md](live-streaming.md)), and `grant_type=refresh_token`
  (see the authentication events note below).
- **`actor_user_id` is nullable** — for self-registration, the actor
  *is* the newly created user (they acted on themselves), not `null`;
  `null` is reserved for events genuinely without an authenticated
  caller in context, none of which exist in the current closed action
  set, but the column stays nullable for forward compatibility.
- **`metadata` is a JSON blob, not typed per-action columns** — the
  relevant details differ per `action` (e.g. `{before, after}` for a
  quota change vs. `{role, scope_type, scope_id, subject_type,
  subject_id}` for a role grant); a dedicated column set per action type
  was rejected as type-safety that doesn't pay for itself on a
  write-once, human-read record.
- **`GET /v1/audit-log`** — `admin` only (not `owner`, even for their own
  group — a deliberate narrowing, see `design.md`'s Risks for why), with
  `actor_user_id`/`action`/`target_type`/`target_id`/`from`/`to` filters
  and keyset pagination, the same pattern as `GET /v1/logs`.
- **Two retention periods, both off by default** (decision 46). One
  covers authentication events, the other everything else; either can be
  left unset, which means "keep forever" — and unset is the default, so
  upgrading the server never silently deletes anyone's history. The split
  exists because the two classes differ in every way that matters:
  administrative mutations are few, valuable for years, and contain
  nothing but resource ids; `auth.*` events are generated by outside
  traffic and carry `client_ip`/`user_agent`, where long storage is a
  liability rather than a feature.
- **Which class a row belongs to is decided by an explicit list of
  `action` values**, not by a `LIKE 'auth.%'` prefix match — the action
  set is closed, so the purge query can use `IN (...)`/`NOT IN (...)`
  and the existing index on `action`. The cost is manual discipline
  (a future `auth.*` action has to be added to the list), guarded by a
  test that requires every value of the closed set to land in exactly
  one class. `audit.purged` itself counts as administrative, so the
  explanation for a deletion outlives the rows it deleted.
- **Deletion rides the periodic purge job that already enforces
  `retention_days` on `log_entries`** (decision 14) — no second timer. It
  deletes in chunks rather than one statement: WAL lets readers run
  during a write, but not a second writer, and a single `DELETE` over
  millions of rows would block log ingestion for its whole duration.
- **A purge that deleted anything writes `audit.purged`**
  (`actor_user_id: null`, `metadata` carrying the class, the row count,
  and the age boundary). Without it, an admin who finds last year's
  history missing can't tell a configured policy from someone covering
  their tracks — which is the one question the audit log exists to
  answer. One row per class per pass, so its volume is bounded by the
  timer interval, not by traffic.
- **Nothing deletes an audit row by hand.** There is no
  `DELETE /v1/audit-log`, no per-row delete, no UI action, and no role
  that can do it; the retention policy is also configured at server
  startup rather than through the API. An admin is a subject of this log,
  not its owner — being able to selectively erase one's own trail would
  void the whole record. (Whoever has the database file can of course do
  as they like; the API was never what stopped that level of access.)
- **The policy in force is returned by `GET /v1/audit-log`** alongside
  `items`/`next_cursor`, so an admin searching for a two-year-old event
  sees why it isn't there, in the same response where they looked for it.

## A risk worth carrying forward: keeping this in sync

The closed `action` enum needs manual discipline — every future mutating
endpoint has to remember to write an audit row; nothing enforces a 1:1
correspondence automatically. `openspec-verify-change` (tasks.md's
finalization step) checks this once, for this change's own endpoints —
it won't catch a regression introduced by a later, unrelated change.
