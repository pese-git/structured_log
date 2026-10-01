## 1. Принципал и формат секретного ключа

- [x] 1.1 `lib/src/auth/principal.dart` (новый файл): sealed `Principal` с вариантами `UserPrincipal(VerifiedIdentity identity)`, `ProjectPrincipal(int projectId)`, `AnonymousPrincipal()` (decision 2). Без зависимости на `shelf` — это модель слоя `auth/`, а не HTTP.
- [x] 1.2 `lib/src/auth/hashing.dart`: добавить `const projectSecretKeyPrefix = 'slk_'` и `generateProjectSecretKey()` = префикс + `generateRandomToken()`; `generateRandomToken()` не трогать — им же генерируются refresh-токены, которым префикс не нужен (decision 5). Хэшируется значение вместе с префиксом.
- [x] 1.3 `lib/src/http/routes/secret_keys_route.dart`: `createSecretKey` выдаёт ключ через `generateProjectSecretKey()`.
- [x] 1.4 Тесты `test/auth/hashing_test.dart`: выданный ключ начинается с `slk_`; `hashToken` считается от строки с префиксом; `generateRandomToken()` префикса не несёт.

## 2. Единый резолвящий middleware

- [x] 2.1 `lib/src/http/principal_middleware.dart` (новый файл): `Middleware principalMiddleware(IdentityProvider provider, StructuredLogDatabase db)` — читает `Authorization: Bearer <...>`; значение с префиксом `slk_` резолвит через поиск по `hashToken(...)` в `project_secret_keys` (отвергая отозванные) в `ProjectPrincipal`; значение без префикса — через `provider.verifyAccessToken` в `UserPrincipal`; отсутствие заголовка, неподходящую схему заголовка и любую неудачу резолвинга — в `AnonymousPrincipal`. Никогда не возвращает ответ сам, всегда вызывает `innerHandler` (decision 1, decision 4).
- [x] 2.2 В том же файле — расширение `PrincipalRequest on Request`: `Principal get principal` (для не прошедшего middleware запроса — `AnonymousPrincipal`, не бросать), плюс аксессоры из задачи 3.1.
- [x] 2.3 Удалить `lib/src/http/auth_middleware.dart` и `lib/src/http/project_key_middleware.dart`; расширения `verifiedIdentity`/`authenticatedProjectId` вместе с ними (их вызовы переезжают на аксессоры в разделе 3).
- [x] 2.4 Тесты `test/http/principal_middleware_test.dart`: access-токен → `UserPrincipal`; ключ с префиксом → `ProjectPrincipal` с верным `project_id`; отозванный ключ → `AnonymousPrincipal`; ключ без префикса → `AnonymousPrincipal` (в БД не ходим); истёкший/с неверным `tv` токен → `AnonymousPrincipal`; нет заголовка → `AnonymousPrincipal`; во всех случаях middleware пропускает запрос дальше, а не отвечает сам.

## 3. Аксессоры требования принципала

- [x] 3.1 `requireUser({bool allowTemporaryPassword = false})` → `VerifiedIdentity` и `requireProject()` → `int` на `Request`: бросают `ApiError.unauthorized(<сообщение, специфичное для требуемого типа>)` при несовпадении типа принципала (decision 3); `requireUser` дополнительно бросает 403 `must_change_password` при взведённом флаге, если не передан `allowTemporaryPassword: true` (decision 6). Сообщения сохранить из удаляемых middleware («Missing bearer access token.» / «Invalid, expired, or revoked access token.» / «Missing project secret key.» — свести к формулировкам, не различающим «нет» и «недействителен», как требует спека).
- [x] 3.2 Удалить `lib/src/http/must_change_password_middleware.dart` и его тест (`test/http/must_change_password_middleware_test.dart`) — поведение переехало в 3.1 и тестируется там же.
- [x] 3.3 Тесты `test/http/principal_middleware_test.dart` (или отдельный `require_accessors_test.dart`): все четыре отказных пути `requireUser`, оба отказных пути `requireProject`, и opt-out `allowTemporaryPassword: true`.

## 4. Перевод хендлеров

- [x] 4.1 `lib/src/http/routes/logs_route.dart`: `ingestLogs` — `request.authenticatedProjectId` → `request.requireProject()`; `queryLogs` — `request.verifiedIdentity` → `request.requireUser()`.
- [x] 4.2 `lib/src/http/routes/change_password_route.dart`: `request.requireUser(allowTemporaryPassword: true)` — единственный реализованный эндпоинт из списка исключений гейта.
- [x] 4.3 `lib/src/http/routes/groups_route.dart`, `projects_route.dart`, `secret_keys_route.dart`: 8 оставшихся обращений `request.verifiedIdentity` → `request.requireUser()`.
- [x] 4.4 `lib/src/http/routes/auth_route.dart` (`issueToken`, `revokeToken`, `healthCheck`) не меняется — эндпоинты публичные, креденшелы проверяет `TokenService`.

## 5. Сборка обработчика

- [x] 5.1 `lib/src/http/server.dart`: `principalMiddleware` добавляется в `Pipeline` после `errorHandlingMiddleware`; из таблицы маршрутов убираются `jwtAuth`/`jwtAuthGated`/`projectKeyAuth`, каждая запись сводится к `..verb('<path>', (req) => handler(deps, req))`. Комментарий о двух схемах аутентификации заменяется на описание единой точки со ссылкой на `log-server-auth`.
- [x] 5.2 `test/http/routes/test_helpers.dart`: `authenticatedRequest` кладёт в контекст `UserPrincipal` вместо `VerifiedIdentity` по строковому ключу; добавить `projectKeyRequest(...)` для `ProjectPrincipal`; `shelf_router/params` остаётся как есть.
- [x] 5.3 Обновить существующие тесты маршрутов и `test/http/server_test.dart` под новые хелперы; проверить, что кейсы 401/403, ранее покрывавшиеся тестами удалённых middleware, сохранились.

## 6. Табличная проверка fail-closed

- [x] 6.1 `test/http/route_auth_matrix_test.dart` (новый): таблица всех маршрутов `buildHandler` с явным указанием требуемого принципала (`user` / `project` / `public`). Для каждого не-публичного маршрута — запрос без `Authorization` и запрос с креденшелом другого типа дают 401; для публичных — 401 по причине аутентификации не возвращается (decision 7).
- [x] 6.2 Сверить таблицу теста с таблицей маршрутов `buildHandler` — количество записей должно совпадать; расхождение означает, что маршрут добавлен мимо проверки.

## 7. Документация и завершение

- [x] 7.1 `docs/architecture/auth.md` + `auth.ru.md`: описание двух независимых middleware заменяется на единую точку + типы принципала + аксессоры; добавить формат ключа с префиксом `slk_`.
- [x] 7.2 `docs/api/http-api.md` + `http-api.ru.md`, `docs/api/errors.md` + `errors.ru.md`: упоминания схемы аутентификации `POST /v1/logs` и 401-поведения при перекрёстном предъявлении креденшелов.
- [x] 7.3 `dart analyze` без замечаний, `dart test` зелёный, `dart format --set-exit-if-changed .` чистый — из `backend/structured_log_server/`; затем `dart run melos run lint` и `dart run melos run test` из корня.
- [x] 7.4 Коммит в формате Conventional Commits (`refactor(structured_log_server)!:` — ломающее изменение формата секретного ключа); `CHANGELOG.md`/`version` не трогать.
