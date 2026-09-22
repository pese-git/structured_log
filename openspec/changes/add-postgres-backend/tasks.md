## 1. Spike: verify raw-SQL placeholder passthrough

- [ ] 1.1 Add `drift_postgres`/`postgres` dependencies and `dialects: [sqlite, postgres]` to `build.yaml` (`backend/structured_log_server/`); regenerate.
- [ ] 1.2 Stand up a throwaway `PgDatabase` against a local/Docker Postgres and run `buildAuditQuerySql`'s dynamic `WHERE` (or an equivalent representative fragment with several `?` placeholders) through `db.customSelect` unmodified. Confirm it returns correct rows.
- [ ] 1.3 Record the result in `design.md`'s Open Questions (or promote it into Decisions if it holds) — if placeholder passthrough does **not** work unmodified, add dialect-branching tasks to this file for every `customSelect`/`customStatement` call site (`log_store.dart`, `query.dart`, `audit_query.dart`, `create_admin.dart`, `bootstrap_admin.dart`, `database.dart`) before continuing past section 2.

## 2. Schema portability

- [ ] 2.1 Remove `.withDefault(currentDateAndTime)()` from the 10 `createdAt` columns in `lib/src/storage/database.dart` (`Users`, `Groups`, `Teams`, `Projects`, `ProjectSecretKeys`, `RoleAssignments`, `RefreshTokens`, `PasswordResetTokens`, `EmailVerificationTokens`, `AuditLogEntries`); every insert call site for these tables now sets `createdAt: Value(clock())` explicitly (inject `DateTime Function() clock`, mirroring the existing pattern in `purge_job.dart`/`rate_limit_middleware.dart`).
- [ ] 2.2 Enumerate and update every insert call site touched by 2.1 (routes, `create_admin.dart`, `bootstrap_admin.dart`) — a test per table asserting `createdAt` is set from the injected clock, not left to a DB default.
- [ ] 2.3 Replace the raw `= 1` boolean literals in `create_admin.dart` (`_activeAdminExists`, `_anyPrimaryAdminEverExisted`) with bound `Variable.withBool(true)` parameters.
- [ ] 2.4 Make the partial unique index `CREATE UNIQUE INDEX idx_users_is_primary_admin ... WHERE is_primary_admin = 1` in `database.dart` dialect-aware (`= 1` for SQLite, `= true` for Postgres), selected by `db.dialect` at migration time — the one DDL literal that can't be parameterized.
- [ ] 2.5 Audit `log_filter.dart`/`query.dart` for any other bare integer/boolean literal in a raw SQL fragment beyond what's already covered (`json_extract`'s own boolean-as-`0`/`1` return value, noted in an existing comment) and port each the same way.

## 3. Executor selection and configuration

- [ ] 3.1 Add `db-backend` (`sqlite`|`postgres`, default `sqlite`) to `serverConfigParams` (`lib/src/config/server_config.dart`), validated against the closed set.
- [ ] 3.2 Add Postgres connection settings: `db-postgres-host`, `-port`, `-database`, `-username` (plain params), `STRUCTURED_LOG_DB_POSTGRES_PASSWORD`/`_FILE` (secret, same convention as the JWT secret), `db-postgres-pool-size`, `db-postgres-ssl-mode` — all required only when `db-backend=postgres` (extend the existing per-command-requirement mechanism, `log-server-config`).
- [ ] 3.2a Make `db-path` required only when `db-backend=sqlite` (or unset) — both for `serve` and `create-admin`, which share the same `ConfigResolver` (`log-server-config`, "Набор обязательных параметров зависит от выполняемой команды" — this change's delta spec). Update `test/config/server_config_test.dart` and any `create-admin` test asserting `--db-path` is unconditionally required.
- [ ] 3.3 `--db-read-pool-size` becomes a no-op with a startup warning (own diagnostics log) when `db-backend=postgres`.
- [ ] 3.4 `StructuredLogDatabase.openPostgres(...)` factory in `database.dart` — builds a `PgDatabase` from an `Endpoint`/`Pool` per the resolved settings, TLS mode applied.
- [ ] 3.5 `bin/server.dart` selects `StructuredLogDatabase.open(...)` vs `.openPostgres(...)` from `ServerConfig.dbBackend`; connection is attempted and validated during the existing pre-listen configuration-check phase — a failure exits `78`, not a runtime error on first query.
- [ ] 3.6 `--print-config` reflects only the settings relevant to the selected backend (Postgres settings hidden/marked n/a under `sqlite`, and vice versa) — same posture as other conditionally-required settings.

## 4. Hot-path ports

- [ ] 4.1 `DriftLogStore._insert` (`log_store.dart`) branches on `db.dialect`: SQLite path unchanged (`last_insert_rowid()` + range read); Postgres path issues one multi-row `INSERT ... VALUES (...), ... RETURNING *` in a single round trip, no id-range assumption.
- [ ] 4.2 A shared test suite for `LogStore.insertBatch`/`insertRows` parameterized over both backends (tagged `postgres` for the Postgres run — see section 6) asserting identical returned rows/order for the same input.
- [ ] 4.3 Verify `LogFilter`'s `context` matching (`log_filter.dart`) against Postgres — either the same `?`-placeholder fragment works unmodified (per the section 1 spike) or gets a `jsonb`-operator branch; add the cross-backend scenario from `specs/log-server-postgres-backend/spec.md` ("Идентичный результат фильтрации по context на обоих backend'ах") as an actual test.

## 5. Migrations

- [ ] 5.1 Confirm `Migrator.createAll()` produces valid Postgres DDL for the full schema (13 tables) against a real Postgres instance — first real exercise of `dialects: [sqlite, postgres]` codegen.
- [ ] 5.2 Confirm drift's own `__schema` version-tracking table is created and the existing `beforeOpen` "refuse a newer schema" check (`database.dart`) behaves identically under Postgres.
- [ ] 5.3 Add a Postgres-tagged test mirroring `test/storage/database_test.dart`'s schema-creation/upgrade coverage, scoped to what's dialect-sensitive (not a full duplicate of every SQLite storage test).

## 6. CI

- [ ] 6.1 Add a `postgres` tag to `dart_test.yaml`, excluded by default alongside `integration` — same split pattern already used there.
- [ ] 6.2 `.github/workflows/ci.yml`: add a Postgres service container to the `structured_log_server` job (or a new job), wait for readiness before the test step (same wait-loop pattern as `chromedriver` in `admin-client-flow`), run `dart test --tags postgres` against it as a separate step alongside the existing `--exclude-tags integration` / `--tags integration` split.

## 7. Documentation

- [ ] 7.1 `docs/operations/configuration.md`/`.ru.md`: new settings in the Reference table (`db-backend`, Postgres connection settings, pool size, TLS mode), a short "PostgreSQL" subsection next to "The database file" explaining what's fixed/configurable and what's out of scope (no data migration path).
- [ ] 7.2 `docs/architecture/technology-stack.md`/`.ru.md`: the storage-engine row becomes "SQLite (default) or PostgreSQL, operator's choice" with the `drift_postgres` rationale.
- [ ] 7.3 `docs/architecture/data-model.md`/`.ru.md`: "Storage engine" section updated to describe both backends and what stays SQLite-only (nothing observable to the API, per `log-server-postgres-backend`).
- [ ] 7.4 `backend/structured_log_server/README.md`/`README.ru.md`: quickstart gains a "running against PostgreSQL instead" variant.
- [ ] 7.5 Root `AGENTS.md`: update the `structured_log_server` section's storage-engine bullet; note the new `postgres` CI tag next to the existing `integration` one.

## 8. Verification

- [ ] 8.1 `dart analyze` clean for `structured_log_server`.
- [ ] 8.2 `dart test` (default + `integration` tags) green, unchanged from before this change — the SQLite path must show zero regression.
- [ ] 8.3 `dart test --tags postgres` green against a real Postgres instance (local Docker or CI service container).
- [ ] 8.4 `dart format --set-exit-if-changed .` clean.
- [ ] 8.5 Manual end-to-end check: start the server once with `--db-backend=postgres` against a local Postgres, run the same operator flow used for previous manual verifications in this project (create admin → group → project → ingest via `structured_log_http` → query → live stream) — confirm parity with the SQLite path.
