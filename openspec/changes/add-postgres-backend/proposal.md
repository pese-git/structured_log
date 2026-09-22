## Why

`structured_log_server` хранит всё в embedded SQLite (`drift`/`NativeDatabase`) — решение, принятое прямым указанием пользователя (decision 2, `add-structured-log-server/design.md`) под self-hosted, «один процесс, один файл» позиционирование сервиса. Для части операторов это ограничение: у них уже есть управляемый PostgreSQL (бэкапы, мониторинг, HA), и они не хотят заводить второй, отдельно обслуживаемый способ хранения ради одного сервиса. Драйвер для этого существует — `drift_postgres` (официальный, тот же автор/репозиторий, что и `drift`) — но не «включается флагом»: у сервера уже есть SQLite-специфичный код (`json_extract` для фильтрации по `context`, `last_insert_rowid()` для получения id вставленной записи, `PRAGMA journal_mode=WAL`/`busy_timeout`/`synchronous`, изолят-based read pool поверх `NativeDatabase.createInBackground`, миграции через `Migrator`/`onUpgrade`, которого `alterTable` на Postgres не поддерживает), который нужно осознанно портировать по диалектам, а не просто переключить executor.

## What Changes

- Новая настройка выбора backend'а хранения: `--db-backend` / `STRUCTURED_LOG_DB_BACKEND` = `sqlite` (по умолчанию, текущее поведение не меняется) | `postgres`. Выбирается **только** при развёртывании — не переключается во время работы процесса, тем же принципом, что и остальная конфигурация («один раз при старте, никакого SIGHUP»).
- Новые настройки подключения к Postgres — host/port/database/username аргументами, пароль — секретом (`STRUCTURED_LOG_DB_PASSWORD`/`_FILE`, тот же файловый конвент, что у JWT-секрета/SMTP-пароля/пароля bootstrap-админа), обязательны только при `--db-backend=postgres`.
- `StructuredLogDatabase` получает выбор executor'а по backend'у: `NativeDatabase` (SQLite, путь не меняется) или `PgDatabase` (`drift_postgres`), при этом схема таблиц (`.drift`/table-классы) остаётся одной на оба диалекта — `build.yaml` получает `dialects: [sqlite, postgres]`, `DateTime`-колонки переводятся на диалект-осведомлённый тип, если drift того потребует.
- Порт трёх мест, завязанных на SQLite буквально:
  - фильтрация по `context` (`json_extract`) — диалект-осведомлённая ветка на `jsonb`-операторы Postgres;
  - id вставленной записи (`last_insert_rowid()`) — переход на `RETURNING id`/`insertReturning`, который drift и так умеет нативно;
  - `PRAGMA journal_mode=WAL`/`busy_timeout`/`synchronous` — SQLite-only, под Postgres не применяются вообще (собственная модель конкурентности/durability).
- **Пул читателей (`--db-read-pool-size`) становится SQLite-only.** Под Postgres конкурентность обслуживает обычный пул соединений (`package:postgres`'s `Pool`), а не изоляты `NativeDatabase.createInBackground(readPool:)` — при `--db-backend=postgres` настройка игнорируется с предупреждением при старте (тот же принцип, что «неизвестная переменная только предупреждает»).
- Миграции схемы: SQLite остаётся на встроенном `Migrator`/`onUpgrade` (без изменений). Postgres — отдельная стратегия, поскольку `Migrator.alterTable` там не поддерживается (сама документация `drift` рекомендует экспортировать схему и вести миграции отдельным инструментом) — решается в `design.md`.
- CI: новый прогон тестов сервера против настоящего PostgreSQL (вероятно, service-контейнер в GitHub Actions) — решается в `design.md`.
- Документация: `docs/operations/configuration.md`/`.ru.md` (новые настройки), `docs/architecture/technology-stack.md`/`.ru.md` и `docs/architecture/data-model.md`/`.ru.md` (раздел «Storage engine» становится «один из двух», не «только SQLite»), корневой `AGENTS.md`.

Вне периметра: `deploy/docker-compose.yml` не меняется — единый SQLite-контейнер остаётся образцовым способом развёртывания; Postgres — явный opt-in для операторов, которым он нужен, не новый дефолт. Переключение backend'а на лету/миграция данных между backend'ами не входит в объём (оператор выбирает один backend при первом запуске на пустой базе; смена backend'а — это отдельная, не автоматизированная эта задачей операция).

## Capabilities

### New Capabilities

- `log-server-postgres-backend`: поведенческие требования, специфичные для Postgres как backend'а — какие настройки обязательны/игнорируются при каждом backend'е, что происходит при недоступном Postgres на старте, как применяются миграции, чем отличается (или не отличается для вызывающего API) фильтрация по `context`.

### Modified Capabilities

- `log-server-storage`: требования, буквально называющие SQLite/JSON1/WAL («Требование: Хранение записи лога... SHALL сохраняться в SQLite», «Требование: Фильтрация по произвольным полям context через JSON1», «Требование: Режим журналирования WAL») обобщаются на «настроенный backend хранения» — поведение для вызывающего (round-trip произвольных полей `context`, отсутствие блокировки чтения при конкурентной записи) остаётся тем же требованием независимо от backend'а, конкретный механизм (JSON1 vs `jsonb`, WAL vs Postgres MVCC) — становится деталью backend'а, описанной в `log-server-postgres-backend`/`design.md`, а не в тексте этого требования.
- `log-server-config`: новые требования на `--db-backend`, обязательность/опциональность настроек подключения к Postgres в зависимости от выбранного backend'а, обработку пароля как секрета по уже существующему конвенту.

## Impact

- `backend/structured_log_server/pubspec.yaml` — новая зависимость `drift_postgres` (+ `postgres`), `build.yaml` — `dialects: [sqlite, postgres]`.
- `lib/src/storage/database.dart` — выбор executor'а по backend'у; путь SQLite не меняется в поведении.
- `lib/src/storage/log_store.dart`, `log_filter.dart`, `query.dart` — диалект-осведомлённые ветки для id-после-вставки и JSON-фильтрации.
- `lib/src/config/` — новые параметры (`db-backend`, host/port/database/username/password для Postgres), валидация обязательности по выбранному backend'у, `--print-config` отражает только релевантные текущему backend'у настройки.
- Стратегия миграций для Postgres — новый механизм (решается в `design.md`), не расширение текущего `Migrator`.
- `bin/server.dart` — сборка `StructuredLogDatabase` по backend'у из конфигурации.
- `.github/workflows/ci.yml` — новый прогон/матричная нога против настоящего Postgres.
- Документация: `docs/operations/configuration.md`/`.ru.md`, `docs/architecture/technology-stack.md`/`.ru.md`, `docs/architecture/data-model.md`/`.ru.md`, корневой `AGENTS.md`.
- Клиентские пакеты (`structured_log_admin_client`, `structured_log_http`) не затрагиваются — контракт HTTP API не меняется, backend хранения — деталь сервера.
