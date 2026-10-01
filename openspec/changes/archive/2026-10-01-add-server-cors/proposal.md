## Why

`structured_log_server` не отдаёт CORS-заголовков вообще — решение зафиксировано как требование в `specs/log-server-api` (change `add-structured-log-server`, decision 35.3/задача 6.7): единственный поддерживаемый способ развёртывания браузерного клиента — тот же origin, что у API, за общим обратным прокси. Это неудобно для одного законного сценария — локальной разработки на хосте без docker-compose/nginx, когда сервер и Flutter-клиент поднимаются на разных портах вручную: браузер отвергает запрос без `Access-Control-Allow-Origin`, а preflight `OPTIONS` отвечает `404` (нет такого маршрута). При тестировании user-management Этапа 3 (16.09.2026) это потребовало ручного обходного прокси-шима — временного и не входящего в репозиторий.

## What Changes

- Добавить опциональный список разрешённых origin — флаг `--cors-allowed-origins` / переменная `STRUCTURED_LOG_CORS_ALLOWED_ORIGINS`, значения через запятую. По умолчанию список пуст, и поведение не меняется: заголовков CORS нет, preflight `OPTIONS` по-прежнему `404`.
- При непустом списке — новый middleware в общем `Pipeline`: на preflight `OPTIONS` с `Origin`, входящим в список, отвечает `204` с `Access-Control-Allow-Origin` (значение запрошенного origin, не `*` — токен в `Authorization` не должен уходить туда, куда попало), `Access-Control-Allow-Methods`, `Access-Control-Allow-Headers: Authorization, Content-Type`; на обычный запрос с таким `Origin` — добавляет `Access-Control-Allow-Origin` к обычному ответу. Origin вне списка не получает заголовков и не меняет код ответа — как если бы CORS был выключен.
- Уточнить SHALL-требование `specs/log-server-api`: по умолчанию поведение прежнее (нет заголовков, preflight не выделен); при непустом списке разрешённых origin — заголовки присутствуют для origin из списка и preflight обрабатывается.
- Расширить сторож `test/http/cors_test.dart`: существующие тесты (нет заголовков и без списка) остаются как тесты дефолтного поведения; добавляются тесты на явное включение — origin из списка получает заголовки и `204` на preflight, origin вне списка — нет.
- Обновить документацию, где отсутствие CORS описано как абсолютное: `AGENTS.md` (корень), `README.md`/`README.ru.md` и `docs/operations/configuration.md`/`.ru.md` пакета `structured_log_server` — снять формулировку «нет вообще» на «по умолчанию нет, включается явным списком origin».

Вне объёма: `deploy/docker-compose.yml` не меняется — единый origin остаётся образцовым способом продакшен-развёртывания, CORS не подразумевает и не поощряет открытие API на отдельный домен без прокси. `Access-Control-Allow-Credentials` не нужен — клиент передаёт токен в `Authorization`, не через cookie.

## Capabilities

### New Capabilities

<!-- нет -->

### Modified Capabilities

- `log-server-api`: SHALL-требование «сервер не отдаёт CORS-заголовков» становится условным — выполняется по умолчанию (пустой список разрешённых origin) и снимается для origin из явно заданного списка.

## Impact

- Капабилити `log-server-api` описана в ещё не заархивированной change `add-structured-log-server` (в `openspec/specs/` её пока нет) — delta этой change читается поверх той, и при архивации порядок должен быть «сначала `add-structured-log-server`, потом эта» (тот же порядок уже зафиксирован в `unify-server-auth` для `log-server-auth`).
- `backend/structured_log_server/lib/src/config/` — новое поле конфигурации, разбор флага/переменной (список origin через запятую), `--print-config` печатает его как есть (список origin не секрет).
- `backend/structured_log_server/lib/src/http/` — новый `cors_middleware.dart`, вшивается в общий `Pipeline` в `server.dart` **до** аутентификации: preflight `OPTIONS` не несёт `Authorization` и не должен доходить до `principal_middleware`/обработчиков маршрутов.
- `backend/structured_log_server/test/http/cors_test.dart` — расширяется (не переписывается с нуля): текущие проверки остаются, добавляются новые на включённый CORS.
- `backend/structured_log_server/test/config/` — тест на разбор новой настройки (список origin, дефолт — пусто).
- Документация: `AGENTS.md` (корень), `backend/structured_log_server/README.md`/`README.ru.md`, `docs/operations/configuration.md`/`.ru.md`.
- Клиентские пакеты (`structured_log_admin_client`, `structured_log_http`) не затрагиваются — контракт `POST`/`GET` не меняется, меняются только заголовки на предъявленный `Origin`.
