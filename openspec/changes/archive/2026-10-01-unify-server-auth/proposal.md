## Why

`structured_log_server` аутентифицирует запросы двумя независимыми путями — JWT bearer для management-эндпоинтов и `GET /v1/logs`, секретный ключ проекта для `POST /v1/logs` — и оба приезжают в одном и том же заголовке `Authorization: Bearer <...>`. Поскольку схема выбирается не по пути, а по паре «путь + метод» (`GET` и `POST` на `/v1/logs` аутентифицируются по-разному), ни один из двух middleware нельзя поставить в общий `Pipeline`: каждый навешивается поточечно на свой маршрут в `buildHandler` (решение зафиксировано в `tasks.md` 6.4 change `add-structured-log-server`). К этому добавляется третий поточечный слой — гейт `mustChangePasswordMiddleware`, который применяется ко всем JWT-маршрутам, кроме явного списка исключений.

Цена такой раскладки растёт вместе с API. Список исключений гейта смены пароля по спеке уже включает четыре эндпоинта (`POST /v1/auth/change-password`, `DELETE /v1/users/me`, `POST`/`DELETE /v1/auth/token`), из которых реализован один; «исключение по пути» в поточечной модели выражается только тем, что автор нового маршрута вспомнил не надеть обёртку. В `specs/` change `add-structured-log-server` описано ~35 эндпоинтов против 15 реализованных, и каждый новый требует вручную выбрать одну из трёх комбинаций обёрток. Момент для унификации удачный и по внешней причине: `structured_log_http` ещё скаффолдинг (Этап 0), ни один клиент не хранит выданный секретный ключ — формат ключа можно менять без миграции.

## What Changes

- Ввести единый тип принципала — sealed-иерархию `Principal` с вариантами «пользователь» (текущий `VerifiedIdentity`), «проект» (id проекта, резолвнутый по секретному ключу) и «аноним» (креденшел не предъявлен или не распознан).
- Заменить `authMiddleware` + `projectKeyMiddleware` одним middleware в общем `Pipeline`, который **резолвит, но не отвергает**: читает `Authorization: Bearer <...>`, определяет тип креденшела, кладёт в контекст запроса соответствующий `Principal` — и передаёт запрос дальше в любом случае, включая случай отсутствующего или недействительного креденшела. Отвергать он не может: `/healthz`, `POST`/`DELETE /v1/auth/token` уже сейчас обслуживаются без аутентификации, а по спеке к ним добавятся `POST /v1/auth/register`, `/v1/auth/password-reset`, `/v1/auth/verify-email`.
- Перенести выдачу 401 в хендлеры — через типизированные аксессоры `Request.requireUser()` / `Request.requireProject()`, бросающие `ApiError.unauthorized()` (общий `errorHandlingMiddleware` уже превращает `ApiError` в JSON-конверт). Предъявление секретного ключа проекта management-эндпоинту и предъявление access-токена эндпоинту приёма логов становятся одинаково 401 — сейчас это обеспечивается тем, что на маршруте физически стоит другой middleware, после унификации SHALL обеспечиваться типом принципала.
- Свернуть `mustChangePasswordMiddleware` в параметр аксессора: `requireUser()` по умолчанию отвергает учётную запись с временным паролем, `requireUser(allowTemporaryPassword: true)` — явный opt-out для эндпоинтов из списка исключений. Список исключений перестаёт быть списком путей и становится точечным флагом в теле того хендлера, который является исключением.
- **BREAKING** (для ещё не выпущенного API): секретный ключ проекта SHALL генерироваться с фиксированным префиксом `slk_`, по которому единый middleware отличает его от JWT. Префикс — часть значения ключа, формат заголовка (`Authorization: Bearer <project-secret-key>`) не меняется, `structured_log_http` не затрагивается. Побочная выгода — узнаваемость ключа для secret-scanning и при разборе инцидентов; альтернатива (различать по форме токена: JWT — три сегмента через точку, ключ — base64url без точек) рассмотрена в `design.md` и отклонена.

Вне объёма этой change: внедрение `shelf_router_generator` (отдельное решение, которое унификация лишь разблокирует, но не требует); изменение схемы выдачи/отзыва токенов, RBAC, любых требований `log-server-rbac`.

## Capabilities

### New Capabilities

<!-- нет -->

### Modified Capabilities

- `log-server-auth`: единая точка аутентификации вместо двух независимых middleware — добавляется требование о резолвинге любого предъявленного креденшела в один из типов принципала и о 401 при несоответствии типа принципала эндпоинту; уточняется требование к формату секретного ключа проекта (фиксированный префикс `slk_`).

## Impact

- Капабилити `log-server-auth` описана в ещё не заархивированной change `add-structured-log-server` (в `openspec/specs/` её пока нет) — delta этой change читается поверх той, и при архивации порядок должен быть «сначала `add-structured-log-server`, потом эта».
- `backend/structured_log_server/lib/src/http/auth_middleware.dart` и `project_key_middleware.dart` — схлопываются в один `principal_middleware.dart` (+ `lib/src/auth/principal.dart` с sealed-иерархией); `must_change_password_middleware.dart` удаляется, его поведение переезжает в аксессор.
- `backend/structured_log_server/lib/src/http/server.dart` — `buildHandler` теряет поточечные обёртки `jwtAuthGated`/`projectKeyAuth`; таблица маршрутов схлопывается до «путь → хендлер», middleware уезжает в `Pipeline`.
- Все шесть файлов `lib/src/http/routes/*.dart` — 10 обращений `request.verifiedIdentity` заменяются на `requireUser()`, `request.authenticatedProjectId` в `ingestLogs` — на `requireProject()`.
- `backend/structured_log_server/lib/src/auth/hashing.dart` — `generateRandomToken()` получает префикс для секретных ключей проектов (но не для refresh-токенов, которые генерируются той же функцией).
- Тесты: `test/http/auth_middleware_test.dart` + `project_key_middleware_test.dart` + `must_change_password_middleware_test.dart` заменяются тестами единого middleware и аксессоров; `test/http/routes/test_helpers.dart` строит `Principal` вместо ручной подделки контекста; `test/http/server_test.dart` дополняется кейсами перекрёстного предъявления креденшелов.
- `structured_log_http`, `structured_log` и Flutter-пакеты не затрагиваются. Внешний HTTP-контракт не меняется, кроме значения секретного ключа.
