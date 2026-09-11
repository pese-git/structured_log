## 1. Скаффолдинг пакетов

- [ ] 1.1 Создать `structured_log_server/`: `pubspec.yaml` (зависимости `shelf`, `shelf_router`, `drift`, `sqlite3`, `dart_jsonwebtoken`, `bcrypt`, `structured_log`; dev-зависимости `drift_dev`, `build_runner`), `lib/structured_log_server.dart` (barrel), `bin/`, `test/`, `example/`; `LICENSE` скопирован; `*.g.dart` добавлен в `.gitignore` пакета
- [ ] 1.2 Создать `structured_log_http/`: `pubspec.yaml` (единственная зависимость — `structured_log`), `lib/structured_log_http.dart` (barrel), `test/`, `example/`; `LICENSE` скопирован
- [ ] 1.3 Добавить оба пакета в `packages:` корневого [melos.yaml](../../melos.yaml); включить их в scope скриптов `analyze`/`format`/`format:check`/`test:dart`; задокументировать шаг `dart run build_runner build --delete-conflicting-outputs` для `structured_log_server`
- [ ] 1.4 `melos bootstrap`/`dart run build_runner build`/`dart analyze` на пустых пакетах

## 2. structured_log_server — мультитенантная схема хранения

- [ ] 2.1 Определить drift `Table`-классы (`lib/src/storage/database.dart`): `Users`, `Groups`, `Teams`, `TeamMembers`, `Projects`, `ProjectSecretKeys`, `RoleAssignments`, `RefreshTokens`, `ProjectUsage`, `LogEntries` (с `project_id`, `size_bytes`) — согласно `specs/log-server-storage/spec.md`; `@DriftDatabase`-аннотированный класс БД, `PRAGMA journal_mode=WAL`; сгенерировать `database.g.dart`
- [ ] 2.2 Индексы: `log_entries` — `project_id`/`timestamp`/`level`/`category`/`session_id`/`request_id` и составной `(project_id, level, timestamp)`; уникальный индекс на `users.username`; индекс на `refresh_tokens.user_id`
- [ ] 2.3 Миграция схемы при старте (`MigrationStrategy`/`onUpgrade`, идемпотентная)
- [ ] 2.4 Реализовать `LogStore`/`DriftLogStore` (`insertBatch` с привязкой к `project_id`, `query` с фильтрами из `specs/log-server-api`) и построение фильтра (`lib/src/storage/query.dart`): типизированные поля через query-builder drift, `LIKE`/`json_extract` через `customSelect`, keyset-пагинация по `id`
- [ ] 2.5 Юнит-тесты storage-слоя на сценарии из `specs/log-server-storage/spec.md`: привязка записи к проекту, использование составного индекса, round-trip произвольного context-поля, независимость received_at от timestamp, согласованность scope_id в role_assignments, сохранность данных после рестарта, отсутствие блокировки чтения при конкурентной записи (WAL)

## 3. structured_log_server — аутентификация (log-server-auth)

- [ ] 3.1 Хэширование паролей (`bcrypt`), секретных ключей проектов и refresh-токенов (SHA-256 случайного токена, генерируемого `Random.secure()`) — `lib/src/auth/hashing.dart`
- [ ] 3.2 `POST /v1/auth/register`: создание пользователя по `username`/паролю без `RoleAssignment`, доступен только при `ServerConfig.registrationEnabled == true` (403 иначе), 409 при занятом `username`
- [ ] 3.3 `POST /v1/auth/token` (form-encoded, `application/x-www-form-urlencoded`), диспетчеризация по `grant_type`:
  - `grant_type=password` — проверка `username`/`password`, выдача access-JWT (`dart_jsonwebtoken`, HS256, подписывающий секрет из `ServerConfig`, короткий срок жизни) с claims `iss`/`sub`/`iat`/`exp`/`jti`/`preferred_username` (без списка ролей) + refresh-токена (хранится хэшем в `refresh_tokens`)
  - `grant_type=refresh_token` — проверка хэша/срока/`revoked_at` refresh-токена, ротация (отзыв предъявленного + выдача новой пары), отзыв всех refresh-токенов пользователя при повторном использовании уже отозванного
  - Тело ответа — RFC 6749 §5.1 (`access_token`/`token_type`/`expires_in`/`refresh_token`/`refresh_expires_in`); ошибки — RFC 6749 §5.2 (`error`/`error_description`), отдельно от общего JSON-конверта ошибок остального API
- [ ] 3.4 `DELETE /v1/auth/token` (form-encoded, поле `refresh_token`, RFC 7009): немедленный отзыв предъявленного refresh-токена; 200 с пустым телом независимо от валидности/существования токена, 400 (`invalid_request`) только при отсутствии поля `refresh_token`
- [ ] 3.5 Access-JWT-auth middleware для management-эндпоинтов и `GET /v1/logs`: проверка подписи/срока действия, извлечение `sub`, 401 при отсутствии/невалидном/истёкшем токене
- [ ] 3.6 Auth middleware приёма логов: резолвинг секретного ключа проекта из `Authorization: Bearer`, 401 при отсутствии совпадения или `revoked_at != null`
- [ ] 3.7 Юнит-тесты на сценарии из `specs/log-server-auth/spec.md`: регистрация вкл/выкл, занятый username, `grant_type=password`/`refresh_token` (успех/ошибка в формате RFC 6749), ротация refresh-токена, отзыв всей цепочки при реюзе отозванного refresh-токена, `DELETE /v1/auth/token` (включая одинаковый 200-ответ на валидный/невалидный/несуществующий токен), отсутствие plaintext-пароля в БД, немедленное действие отзыва прав несмотря на валидный access-токен, секретный ключ виден только один раз, несколько активных ключей одновременно

## 4. structured_log_server — RBAC (log-server-rbac)

- [ ] 4.1 Резолвинг эффективных прав пользователя (`lib/src/rbac/authorizer.dart`): прямые `role_assignments` пользователя + через членство в командах, с учётом иерархии областей (global ⊇ group ⊇ project)
- [ ] 4.2 Правила выдачи/отзыва ролей (`POST`/`DELETE /v1/role-assignments`): admin — без ограничений; owner группы `G` — только role ∈ {owner, user} на scope ∈ {group:G, project ∈ G}; user — запрещено полностью
- [ ] 4.3 Authorization middleware для management-эндпоинтов (`teams`/`projects`/`project_secret_keys`/`users`/`groups`): владелец/admin — запись, user — только чтение в рамках своей области
- [ ] 4.4 Юнит-тесты на сценарии из `specs/log-server-rbac/spec.md`: наследование прав по иерархии областей (в т.ч. на новый проект, созданный после гранта на группу), немедленное действие членства/выхода из команды, запрет owner выдавать admin или права вне своей группы, запрет user на любую выдачу ролей, ограничение создания users/groups ролью admin

## 5. structured_log_server — management API

- [ ] 5.1 `POST /v1/users`, `GET /v1/users` (admin only)
- [ ] 5.2 `POST /v1/groups`, `GET /v1/groups` (создание — admin only; список — по видимым вызывающему группам)
- [ ] 5.3 `POST /v1/groups/:groupId/teams`, `POST /v1/teams/:teamId/members`, `DELETE /v1/teams/:teamId/members/:userId` (owner группы/admin)
- [ ] 5.4 `POST /v1/groups/:groupId/projects` (создание с обязательным `retention_days`, опциональными `max_entries`/`max_bytes` — `specs/log-server-quotas`), `PATCH /v1/projects/:id` (изменение квоты), `GET /v1/projects/:id` (owner группы/user с доступом/admin)
- [ ] 5.5 `POST /v1/projects/:id/secret-keys` (создание/ротация — ключ в открытом виде только в ответе на создание), `GET /v1/projects/:id/secret-keys` (только метаданные), `DELETE /v1/projects/:id/secret-keys/:keyId` (отзыв)
- [ ] 5.6 `POST /v1/role-assignments`, `DELETE /v1/role-assignments/:id` — вызывает authorization middleware из раздела 4
- [ ] 5.7 Унифицировать формат ошибок (`lib/src/errors.dart`): доменные ошибки → структурированный JSON для 400/401/403/404/413/507/500

## 6. structured_log_server — приём и запрос логов (log-server-api)

- [ ] 6.1 `POST /v1/logs`: auth секретным ключом проекта, валидация записей батча, частичный приём с отчётом об отклонённых (`validation_error`/`quota_exceeded` из раздела 7), 413 при превышении размера тела
- [ ] 6.2 `GET /v1/logs`: JWT-auth, обязательный `project_id` или `group_id`, проверка через authorization middleware (раздел 4), остальные фильтры и keyset-пагинация из `specs/log-server-api/spec.md`
- [ ] 6.3 `GET /healthz` без аутентификации
- [ ] 6.4 Собрать сервер (`lib/src/http/server.dart`): `Pipeline` + middleware (JWT-auth/secret-key-auth по маршруту, authorization, error-handling) + `shelf_router` + `shelf_io.serve`
- [ ] 6.5 Юнит-тесты на сценарии из `specs/log-server-api/spec.md`: приём/отказ по ключу, частичный приём, лимит размера, доступ по project_id/group_id (включая 403/404), фильтры, пагинация, структура ошибок

## 7. structured_log_server — квоты (log-server-quotas)

- [ ] 7.1 `ProjectUsage`: инициализация при создании проекта, атомарное обновление в транзакции вставки батча и очистки
- [ ] 7.2 Проверка `max_entries`/`max_bytes` на приёме, отказ отдельным записям батча с `quota_exceeded`/507 (интегрируется с разделом 6.1)
- [ ] 7.3 Периодический purge job по `retention_days` (конфигурируемый интервал), уменьшающий `ProjectUsage`
- [ ] 7.4 Юнит-тесты на сценарии из `specs/log-server-quotas/spec.md`: обязательность retention_days, проект без лимита объёма, удаление по истечении retention, отказ при превышении max_entries/max_bytes (включая учёт внутри одного батча), эффект изменения квоты через PATCH

## 8. structured_log_server — CLI entrypoint

- [ ] 8.1 `ServerConfig`: host/port/путь к БД/JWT-signing-секрет/лимиты батча/интервал purge job/`registrationEnabled` (CLI-флаг и переменная окружения, по умолчанию `false`) — из аргументов/переменных окружения
- [ ] 8.2 `bin/server.dart`: обычный запуск сервера, graceful shutdown по SIGINT/SIGTERM
- [ ] 8.3 Команда `create-admin --username ... --password ...` (bootstrap первого администратора, отказывает, если admin уже существует — decision 12 `design.md`)

## 9. structured_log_http — клиентский sender

- [ ] 9.1 Реализовать `HttpLogOutput` (`lib/src/http_output.dart`) по паттерну `_SerializedAsyncOutput`/`AsyncFileOutput`: конструктор принимает URL сервера и секретный ключ проекта, сериализованная очередь, `catchError` на каждом шаге, `flushed`
- [ ] 9.2 Батчинг по размеру/таймауту, отправка `POST /v1/logs` с `Authorization: Bearer <project-secret-key>`
- [ ] 9.3 Retry с backoff на сетевых ошибках/5xx, без retry на 4xx
- [ ] 9.4 Верхний предел буфера в памяти с вытеснением самых старых записей при переполнении
- [ ] 9.5 Юнит-тесты на сценарии из `specs/structured-log-http-sender/spec.md`

## 10. Интеграционное тестирование

- [ ] 10.1 `structured_log_server/test/integration_test.dart`: реальный `HttpServer` на порту 0, сквозной сценарий — `create-admin` → создание токена admin'ом → создание группы/проекта (с квотой)/секретного ключа → приём логов по ключу → самостоятельная регистрация пользователя (сервер запущен с `registrationEnabled=true`) → выдача роли `user` на проект → создание токена этим пользователем → `GET /v1/logs` (доступ разрешён на «свой» проект, 403 на чужой) → превышение квоты отклоняет запись → `refresh` выдаёт новую пару и инвалидирует старую → `DELETE /v1/auth/token` → повторное использование отозванного refresh-токена отклоняется и отзывает остальные
- [ ] 10.2 Отдельный тест: сервер запущен с `registrationEnabled=false` (или по умолчанию) — `POST /v1/auth/register` отвечает 403
- [ ] 10.3 Ручной smoke test (`dart run bin/server.dart`/`create-admin`, `HttpLogOutput`, `curl` с access-токеном и с секретным ключом) — зафиксировать результат в этой задаче

## 11. CI

- [ ] 11.1 Добавить в [.github/workflows/ci.yml](../../.github/workflows/ci.yml) отдельный job для `structured_log_server`/`structured_log_http` (матрица по пакету, `dart-lang/setup-dart`, только `ubuntu-latest`): `pub get` → (для `structured_log_server`: `dart run build_runner build --delete-conflicting-outputs`) → `format --set-exit-if-changed` → `analyze` → `test`
- [ ] 11.2 Прогнать на GitHub Actions, убедиться, что все job'ы зелёные

## 12. Документация и финализация

- [ ] 12.1 `README.md`/`README.ru.md` для `structured_log_server` (установка, bootstrap admin, создание группы/проекта/секретного ключа, management API, HTTP-контракт приёма/запроса) и `structured_log_http` (установка, быстрый старт с `HttpLogOutput`)
- [ ] 12.2 Обновить корневые `README.md`/`README.ru.md` и разделы «Структура»/«CI» в [AGENTS.md](../../AGENTS.md)
- [ ] 12.3 `openspec-verify-change`: сверить каждое требование из всех шести спек этой change с кодом и тестами, decisions из `design.md` соблюдены
