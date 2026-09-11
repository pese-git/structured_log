## 1. Скаффолдинг пакетов

- [ ] 1.1 Создать `structured_log_server/`: `pubspec.yaml` (зависимости `shelf`, `shelf_router`, `drift`, `sqlite3`, `dart_jsonwebtoken`, `bcrypt`, `structured_log`; dev-зависимости `drift_dev`, `build_runner`), `lib/structured_log_server.dart` (barrel), `bin/`, `test/`, `example/`; `LICENSE` скопирован; `*.g.dart` добавлен в `.gitignore` пакета
- [ ] 1.2 Создать `structured_log_http/`: `pubspec.yaml` (единственная зависимость — `structured_log`), `lib/structured_log_http.dart` (barrel), `test/`, `example/`; `LICENSE` скопирован
- [ ] 1.3 Добавить оба пакета в `packages:` корневого [melos.yaml](../../melos.yaml); включить их в scope скриптов `analyze`/`format`/`format:check`/`test:dart`; задокументировать шаг `dart run build_runner build --delete-conflicting-outputs` для `structured_log_server`
- [ ] 1.4 `melos bootstrap`/`dart run build_runner build`/`dart analyze` на пустых пакетах

## 2. structured_log_server — мультитенантная схема хранения

- [ ] 2.1 Определить drift `Table`-классы (`lib/src/storage/database.dart`): `Users` (с `token_version`, по умолчанию 0), `Groups`, `Teams`, `TeamMembers`, `Projects`, `ProjectSecretKeys`, `RoleAssignments`, `RefreshTokens`, `ProjectUsage`, `LogEntries` (с `project_id`, `size_bytes`) — согласно `specs/log-server-storage/spec.md`; `@DriftDatabase`-аннотированный класс БД, `PRAGMA journal_mode=WAL`; сгенерировать `database.g.dart`
- [ ] 2.2 Индексы: `log_entries` — `project_id`/`timestamp`/`level`/`category`/`session_id`/`request_id` и составной `(project_id, level, timestamp)`; уникальный индекс на `users.username`; индекс на `refresh_tokens.user_id`
- [ ] 2.3 Миграция схемы при старте (`MigrationStrategy`/`onUpgrade`, идемпотентная)
- [ ] 2.4 Реализовать `LogStore`/`DriftLogStore` (`insertBatch` с привязкой к `project_id`, `query` с фильтрами из `specs/log-server-api`) и построение фильтра (`lib/src/storage/query.dart`): типизированные поля через query-builder drift, `LIKE`/`json_extract` через `customSelect`, keyset-пагинация по `id`
- [ ] 2.5 Юнит-тесты storage-слоя на сценарии из `specs/log-server-storage/spec.md`: привязка записи к проекту, использование составного индекса, round-trip произвольного context-поля, независимость received_at от timestamp, согласованность scope_id в role_assignments, сохранность данных после рестарта, отсутствие блокировки чтения при конкурентной записи (WAL)

## 3. structured_log_server — аутентификация (log-server-auth)

- [ ] 3.1 Определить публичный интерфейс `IdentityProvider`/`VerifiedIdentity`/`EffectiveRole` (`lib/src/auth/identity_provider.dart`, экспортирован из barrel-файла пакета) — контракт `verifyAccessToken(String bearerToken) -> Future<VerifiedIdentity?>`, `VerifiedIdentity.roles` опционален
- [ ] 3.2 Хэширование паролей (`bcrypt`), секретных ключей проектов и refresh-токенов (SHA-256 случайного токена, генерируемого `Random.secure()`) — `lib/src/auth/hashing.dart`
- [ ] 3.3 `POST /v1/auth/register`: создание пользователя по `username`/паролю без `RoleAssignment`, доступен только при `ServerConfig.registrationEnabled == true` (403 иначе), 409 при занятом `username`
- [ ] 3.4 Резолвинг claims `roles`/`tv` (`lib/src/auth/claims.dart`): по `user_id` собрать плоский снапшот эффективных прав (прямые `role_assignments` + через `team_members`) и прочитать текущий `token_version` — общая функция, используемая и `grant_type=password`, и `grant_type=refresh_token` (каждый раз заново, не переносится из старого токена)
- [ ] 3.5 `POST /v1/auth/token` (form-encoded, `application/x-www-form-urlencoded`), диспетчеризация по `grant_type`:
  - `grant_type=password` — проверка `username`/`password`, выдача access-JWT (`dart_jsonwebtoken`, HS256, подписывающий секрет из `ServerConfig`, короткий срок жизни) с claims `iss`/`sub`/`iat`/`exp`/`jti`/`preferred_username`/`tv`/`roles` (из 3.4) + refresh-токена (хранится хэшем в `refresh_tokens`)
  - `grant_type=refresh_token` — проверка хэша/срока/`revoked_at` refresh-токена, ротация (отзыв предъявленного + выдача новой пары с заново резолвленными `roles`/`tv` из 3.4), отзыв всех refresh-токенов пользователя при повторном использовании уже отозванного
  - Тело ответа — RFC 6749 §5.1 (`access_token`/`token_type`/`expires_in`/`refresh_token`/`refresh_expires_in`); ошибки — RFC 6749 §5.2 (`error`/`error_description`), отдельно от общего JSON-конверта ошибок остального API
- [ ] 3.6 `DELETE /v1/auth/token` (form-encoded, поле `refresh_token`, RFC 7009): немедленный отзыв предъявленного refresh-токена; 200 с пустым телом независимо от валидности/существования токена, 400 (`invalid_request`) только при отсутствии поля `refresh_token`
- [ ] 3.7 Реализовать `LocalIdentityProvider implements IdentityProvider` (`lib/src/auth/local_identity_provider.dart`), оборачивающий 3.4–3.6: `verifyAccessToken` проверяет подпись/срок действия JWT, делает point-lookup `token_version` пользователя по `sub` и сравнивает с claim `tv` (несовпадение → `null`, как любой невалидный токен — эта проверка не часть публичного интерфейса), при совпадении возвращает `VerifiedIdentity` с непустым `roles` из claims
- [ ] 3.8 Access-JWT-auth middleware для management-эндпоинтов и `GET /v1/logs`: вызывает `IdentityProvider.verifyAccessToken` (текущая конфигурация — `LocalIdentityProvider` из 3.7), 401 при `null`; если `VerifiedIdentity.roles` не `null` — авторизация читает роли прямо оттуда, без обращения к `role_assignments`/`team_members`
- [ ] 3.9 Auth middleware приёма логов: резолвинг секретного ключа проекта из `Authorization: Bearer`, 401 при отсутствии совпадения или `revoked_at != null` (отдельный путь, не через `IdentityProvider`)
- [ ] 3.10 Юнит-тесты на сценарии из `specs/log-server-auth/spec.md`: регистрация вкл/выкл, занятый username, `grant_type=password`/`refresh_token` (успех/ошибка в формате RFC 6749), ротация refresh-токена, отзыв всей цепочки при реюзе отозванного refresh-токена, `DELETE /v1/auth/token` (включая одинаковый 200-ответ на валидный/невалидный/несуществующий токен), отсутствие plaintext-пароля в БД, состав `roles` (прямые + через команду), 401 при несовпадении `token_version`, актуальные `roles`/`tv` после `refresh`, `LocalIdentityProvider.verifyAccessToken` возвращает `VerifiedIdentity` с непустым `roles` (контракт `IdentityProvider`), секретный ключ виден только один раз, несколько активных ключей одновременно

## 4. structured_log_server — RBAC (log-server-rbac)

- [ ] 4.1 Резолвинг эффективных прав пользователя из хранилища (`lib/src/rbac/authorizer.dart`, переиспользуется `claims.dart` из 3.4): прямые `role_assignments` пользователя + через членство в командах, с учётом иерархии областей (global ⊇ group ⊇ project) — единственный источник истины (см. `specs/log-server-rbac`, requirement «Резолвинг... не зависит от источника аутентификации»); вызывается и при выдаче токена (3.4), и как fallback-путь из 4.4, когда `VerifiedIdentity.roles == null`
- [ ] 4.2 Каскадное обновление `token_version` (`lib/src/rbac/token_version.dart`): bulk-`UPDATE users SET token_version = token_version + 1` для всех текущих участников команды при изменении team-scoped `RoleAssignment` или членства в ней; одиночный инкремент при изменении прямого `RoleAssignment` пользователя, деактивации (`is_active = false`) или смене пароля — вызывается из соответствующих management-эндпоинтов (5.x, 3.3)
- [ ] 4.3 Правила выдачи/отзыва ролей (`POST`/`DELETE /v1/role-assignments`): admin — без ограничений; owner группы `G` — только role ∈ {owner, user} на scope ∈ {group:G, project ∈ G}; user — запрещено полностью; создание/удаление вызывает 4.2
- [ ] 4.4 Authorization middleware для management-эндпоинтов (`teams`/`projects`/`project_secret_keys`/`users`/`groups`) и `GET /v1/logs`: владелец/admin — запись, user — только чтение в рамках своей области; читает `VerifiedIdentity.roles` из результата `IdentityProvider.verifyAccessToken` (3.8), если `roles != null` — использует их напрямую, если `roles == null` — резолвит через 4.1 (fallback для реализаций `IdentityProvider` без собственных ролей)
- [ ] 4.5 Юнит-тесты на сценарии из `specs/log-server-rbac/spec.md`: наследование прав по иерархии областей (в т.ч. на новый проект, созданный после гранта на группу), появление прав нового участника команды в его следующем токене, каскадный инкремент `token_version` всех участников при изменении team-scoped роли/членства, эквивалентность резолвинга из БД и снапшота в токене (fallback-путь при `roles == null`), запрет owner выдавать admin или права вне своей группы, запрет user на любую выдачу ролей, ограничение создания users/groups ролью admin

## 5. structured_log_server — management API

- [ ] 5.1 `POST /v1/users`, `GET /v1/users`, `PATCH /v1/users/:id` (деактивация `is_active = false` — вызывает инкремент `token_version`, 4.2) (admin only)
- [ ] 5.2 `POST /v1/groups`, `GET /v1/groups` (создание — admin only; список — по видимым вызывающему группам)
- [ ] 5.3 `POST /v1/groups/:groupId/teams`, `POST /v1/teams/:teamId/members`, `DELETE /v1/teams/:teamId/members/:userId` (owner группы/admin; оба последних вызывают каскадный инкремент `token_version` участников, 4.2)
- [ ] 5.4 `POST /v1/groups/:groupId/projects` (создание с обязательным `retention_days`, опциональными `max_entries`/`max_bytes` — `specs/log-server-quotas`), `PATCH /v1/projects/:id` (изменение квоты), `GET /v1/projects/:id` (owner группы/user с доступом/admin; ответ включает `entry_count`/`total_bytes` из `ProjectUsage` рядом с квотой — decision 22 `design.md`, нужно `structured_log_admin_client`)
- [ ] 5.5 `POST /v1/projects/:id/secret-keys` (создание/ротация — ключ в открытом виде только в ответе на создание), `GET /v1/projects/:id/secret-keys` (только метаданные), `DELETE /v1/projects/:id/secret-keys/:keyId` (отзыв)
- [ ] 5.6 `POST /v1/role-assignments`, `DELETE /v1/role-assignments/:id` — вызывает authorization middleware (4.4) и правила выдачи (4.3), сама операция вызывает инкремент `token_version` (4.2: одиночный для subject_type=user, каскадный для subject_type=team)
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

- [ ] 10.1 `structured_log_server/test/integration_test.dart`: реальный `HttpServer` на порту 0, сквозной сценарий — `create-admin` → создание токена admin'ом → создание группы/проекта (с квотой)/секретного ключа → приём логов по ключу → самостоятельная регистрация пользователя (сервер запущен с `registrationEnabled=true`) → выдача роли `user` на проект → создание токена этим пользователем (проверить, что `roles` в claims содержит грант на этот проект) → `GET /v1/logs` (доступ разрешён на «свой» проект, 403 на чужой) → превышение квоты отклоняет запись → отзыв `RoleAssignment` пользователя → повторный `GET /v1/logs` с тем же access-токеном отвечает 401 (несовпадение `token_version`) → `refresh` выдаёт новую пару с актуальными (уже пустыми) `roles` → `DELETE /v1/auth/token` → повторное использование отозванного refresh-токена отклоняется и отзывает остальные
- [ ] 10.2 Отдельный тест: команда с несколькими участниками получает `RoleAssignment` на проект → все текущие участники получают доступ в своём следующем токене; удаление одного участника из команды инвалидирует его уже выданный токен (401), не затрагивая токены остальных участников
- [ ] 10.3 Отдельный тест: сервер запущен с `registrationEnabled=false` (или по умолчанию) — `POST /v1/auth/register` отвечает 403
- [ ] 10.4 Ручной smoke test (`dart run bin/server.dart`/`create-admin`, `HttpLogOutput`, `curl` с access-токеном и с секретным ключом) — зафиксировать результат в этой задаче

## 11. structured_log_admin_client — скаффолдинг и API-клиент

- [ ] 11.1 Создать `structured_log_admin_client/`: `pubspec.yaml` (зависимости `flutter` sdk, `dio`, `flutter_secure_storage`; без зависимости на `structured_log`/`structured_log_server`/`structured_log_http` — decision 19 `design.md`), `lib/main.dart`, `test/`; веб-платформа через `flutter create --platforms=web` (по аналогии с `structured_log_material_example`/`structured_log_fluent_example`); `LICENSE` скопирован
- [ ] 11.2 Добавить пакет в `packages:` корневого [melos.yaml](../../melos.yaml) и в матрицу существующего `flutter`-job'а CI (не новый job)
- [ ] 11.3 `ApiClient` на `dio` (`lib/src/api/api_client.dart`): base URL сервера из конфигурации приложения, interceptor подстановки `Authorization: Bearer <access-token>`, interceptor перехвата 401 → `grant_type=refresh_token` → повтор исходного запроса ровно один раз (`specs/admin-client-auth`)
- [ ] 11.4 Хранилище токенов (`lib/src/auth/token_storage.dart`) на `flutter_secure_storage`; тестовый мок-реализация для юнит/виджет-тестов (без реального secure storage в CI — decision 20/Risks `design.md`)

## 12. structured_log_admin_client — аутентификация (admin-client-auth)

- [ ] 12.1 Экран логина (`username`/пароль → `grant_type=password`), сохранение полученной пары токенов, переход на основной экран
- [ ] 12.2 Экран регистрации (`POST /v1/auth/register`), понятное сообщение при 403 (регистрация отключена на сервере), переход к логину при успехе
- [ ] 12.3 Действие «выйти»: `DELETE /v1/auth/token` (не блокирует очистку локальных токенов при сетевой ошибке — см. `specs/admin-client-auth`), возврат на экран логина
- [ ] 12.4 Автоматический переход на экран логина при неудачном `refresh` (истёкший/отозванный refresh-токен) — из interceptor'а 11.3
- [ ] 12.5 Виджет/юнит-тесты на сценарии из `specs/admin-client-auth/spec.md`: успешный/неверный логин, регистрация вкл/выкл (403), токены не в открытом хранилище, прозрачный refresh при 401 без видимой пользователю ошибки, переход на логин при неудачном refresh, выход очищает токены даже при недоступном сервере

## 13. structured_log_admin_client — управление ресурсами (admin-client-resource-management)

- [ ] 13.1 Экраны пользователей (список/создание, admin only, скрыт из навигации для остальных)
- [ ] 13.2 Экраны групп (список/создание, admin only) и команд с составом (список/создание/добавление-удаление участников, owner группы/admin)
- [ ] 13.3 Экраны проектов (список/создание/редактирование квоты в рамках группы, owner/admin — редактирование; user с доступом — только просмотр), отображение `entry_count`/`max_entries`/`total_bytes`/`max_bytes` вместе (5.4)
- [ ] 13.4 Управление секретными ключами проекта: список метаданных, создание с одноразовым диалогом показа значения (копирование в буфer обмена, предупреждение о единственном показе), отзыв
- [ ] 13.5 UI выдачи/отзыва `RoleAssignment` (роль/область/получатель — пользователь или команда), форма ограничивает выбор ролей/областей согласно правам текущего пользователя (клиентская подсказка — сервер остаётся источником правды)
- [ ] 13.6 Виджет/юнит-тесты на сценарии из `specs/admin-client-resource-management/spec.md`

## 14. structured_log_admin_client — просмотр и поиск логов (admin-client-log-browser)

- [ ] 14.1 Селектор области видимости (проект/группа) — ограничен ресурсами, доступными текущему пользователю; экран списка логов недоступен без выбора
- [ ] 14.2 Элементы управления фильтрами, соответствующие параметрам `GET /v1/logs` (уровень/категория/logger/диапазон времени/correlation ids/`q`/`context.*`), комбинируемые в одном запросе
- [ ] 14.3 Список результатов с постраничной подгрузкой по курсору (без дублирования записей между страницами; сброс пагинации при смене фильтров/области)
- [ ] 14.4 Детальный просмотр записи (все стандартные поля + произвольный `context`)
- [ ] 14.5 Виджет/юнит-тесты на сценарии из `specs/admin-client-log-browser/spec.md`

## 15. CI

- [ ] 15.1 Добавить в [.github/workflows/ci.yml](../../.github/workflows/ci.yml) отдельный job для `structured_log_server`/`structured_log_http` (матрица по пакету, `dart-lang/setup-dart`, только `ubuntu-latest`): `pub get` → (для `structured_log_server`: `dart run build_runner build --delete-conflicting-outputs`) → `format --set-exit-if-changed` → `analyze` → `test`
- [ ] 15.2 Прогнать на GitHub Actions, убедиться, что все job'ы зелёные (включая `structured_log_admin_client` в существующей матрице `flutter`-job'а)

## 16. Документация и финализация

- [ ] 16.1 `README.md`/`README.ru.md` для `structured_log_server` (установка, bootstrap admin, создание группы/проекта/секретного ключа, management API, HTTP-контракт приёма/запроса), `structured_log_http` (установка, быстрый старт с `HttpLogOutput`) и `structured_log_admin_client` (установка, запуск, скриншоты основных экранов)
- [ ] 16.2 Обновить корневые `README.md`/`README.ru.md` и разделы «Структура»/«CI» в [AGENTS.md](../../AGENTS.md)
- [ ] 16.3 `openspec-verify-change`: сверить каждое требование из всех девяти спек этой change с кодом и тестами, decisions из `design.md` соблюдены
