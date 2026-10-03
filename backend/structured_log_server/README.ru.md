# structured_log_server

[![CI](https://github.com/pese-git/structured_log/actions/workflows/ci.yml/badge.svg)](https://github.com/pese-git/structured_log/actions/workflows/ci.yml)

*Read in [English](README.md).*

**Self-hosted сервер логов: собирает логи со всех установок вашего
приложения в одно место, которым вы распоряжаетесь сами, — команда ищет по
ним и видит новые записи в реальном времени.**

На pub.dev не публикуется: это отдельный сервис, а не библиотека, которую
подключают как зависимость.

## Зачем

Логи, записанные через [`structured_log`](https://pub.dev/packages/structured_log),
остаются на устройстве, которое их записало: в телефоне у клиента, на
компьютере в другом офисе, в контейнере, который уже пересоздан. Чтобы
разобраться, что произошло, записи должны лежать там, где вы можете их
прочитать. А отправлять их в сторонний SaaS — значит передавать данные своих
пользователей посторонним и платить за каждый гигабайт.

`structured_log_server` и есть такое место, причём на вашей собственной
инфраструктуре. Приложения отправляют в него записи по HTTP с ключом своего
проекта, а люди читают их через API запросов, поток в реальном времени и
[веб-админку](../../frontend/structured_log_admin_client/). По умолчанию это
один процесс Dart со встроенным файлом SQLite — без брокеров, кэшей и
инструментов миграции; при необходимости вместо SQLite можно взять PostgreSQL.

## Возможности

### Приём, поиск, живая лента

- **Пакетный приём** — `POST /v1/logs` принимает JSON-массив записей с
  аутентификацией секретным ключом проекта; некорректная запись
  отклоняется отдельно, а остальной батч принимается.
- **Поиск** — `GET /v1/logs` фильтрует записи по уровню, категории, логгеру,
  интервалу времени, correlation id и любому полю `context.<поле>`; есть
  полнотекстовый поиск по событию и контексту и постраничный вывод по курсору.
- **Живая лента** — `GET /v1/logs/stream`, Server-Sent Events с теми же
  фильтрами; если переподключиться с `since_id`, поток сначала дошлёт
  пропущенные записи, без повторов.

### Мультитенантность и доступ

- **Группы и проекты** — проекты объединяются в группы; у каждого проекта
  свои секретные ключи (ключ показывается один раз, хранится в виде хэша и
  может быть отозван), квоты и срок хранения, а заблокированный проект
  перестаёт принимать записи.
- **Пользователи** — `admin` создаёт, редактирует, блокирует и удаляет
  учётные записи (`POST`/`GET`/`PATCH`/`DELETE /v1/users`); новая учётная
  запись получает временный пароль, который нужно сменить при первом входе.
- **Команды** — `owner`/`admin` создают команды группы и управляют
  составом (`POST /v1/groups/:groupId/teams`,
  `POST`/`DELETE /v1/teams/:teamId/members`).
- **Роли по областям** — `admin` выдаёт любую роль где угодно; `owner`
  группы выдаёт `owner`/`user` в рамках своей группы и её проектов —
  пользователю или сразу целой команде (`POST`/`DELETE /v1/role-assignments`).
- **Сессии** — JWT access-токены и ротируемые refresh-токены; в браузере
  refresh-токен хранится в cookie `HttpOnly`, которую скрипт прочитать не
  может. При смене пароля можно завершить все остальные сессии.

### Эксплуатация

- **Квоты и срок хранения** — лимиты проекта на число записей и объём, а
  также фоновая очистка записей старше `retention_days` проекта.
- **Ограничение частоты** — token bucket на эндпоинтах аутентификации, по
  адресу и по субъекту, с учётом обратных прокси (`--trusted-proxy-hops`).
- **Аудит** — `GET /v1/audit-log`, только администратору: кто что изменил
  и кто пытался войти; записи из журнала удаляет только его собственная
  очистка по сроку, которая включается отдельно.
- **Хранилище** — SQLite по умолчанию (один файл, без внешних сервисов)
  либо, по выбору оператора, PostgreSQL (`--db-backend=postgres`).
- **Развёртывание** — настройка флагами или переменными окружения, секреты
  только из окружения, CORS выключен, пока не перечислены origin,
  корректная остановка по `SIGTERM`; Dockerfile, docker-compose и
  манифесты Kubernetes — в [deploy/](../../deploy/).
- **Собственная диагностика** — сервер ведёт свой лог через
  `structured_log` и никогда не записывает в него пароли, токены, ключи и
  тела запросов.

## Состояние

Сервер уже работает, но ещё не завершён: всё перечисленное выше доступно
сейчас. Самостоятельная регистрация, восстановление пароля и подтверждение
email описаны в спецификации, но пока не сделаны — учётные записи создаёт
администратор. Что уже есть, а чего пока нет, — в
[tasks.md](../../openspec/changes/add-structured-log-server/tasks.md).

## Место в проекте

Приложения отправляют записи через
[`structured_log_remote_sync`](https://pub.dev/packages/structured_log_remote_sync)
— выход для `structured_log`, который собирает батчи, повторяет отправку и
никогда не задерживает код, который пишет в лог. Операторы и их команды
читают логи в [admin-клиенте](../../frontend/structured_log_admin_client/) —
веб-приложении, которое раздаётся вместе с этим API. Каталог
[deploy/](../../deploy/) командой `./deploy.sh` поднимает оба за одним nginx
на общем origin.
Руководства на
[structured-log.openidealab.com](https://structured-log.openidealab.com/ru/):
[администратора](https://structured-log.openidealab.com/ru/guides/admin-guide/)
(запуск и эксплуатация сервера),
[пользователя](https://structured-log.openidealab.com/ru/guides/user-guide/)
(admin-клиент),
[разработчика](https://structured-log.openidealab.com/ru/guides/developer-guide/)
(отправка логов из приложения).

## Требования

Dart SDK 3.9 или новее. По умолчанию больше ничего: база — встроенный файл
SQLite, никаких брокеров, кэшей и отдельных инструментов миграции запускать
не надо. Для `--db-backend=postgres` нужен уже работающий у оператора сервер
PostgreSQL — см.
[Запуск с PostgreSQL](#запуск-с-postgresql) ниже.

## Запуск

```bash
cd backend/structured_log_server
dart pub get
dart run build_runner build --delete-conflicting-outputs   # drift/freezed/router

export STRUCTURED_LOG_JWT_SECRET="$(openssl rand -base64 48 | tr -d '\n')"
dart run bin/server.dart serve --db-path=./logs.sqlite
```

У секрета подписи намеренно нет CLI-флага: секреты приходят из окружения,
где они не оседают ни в истории шелла, ни в списке процессов.

`dart run bin/server.dart --print-config` печатает все действующие настройки
и откуда каждая взялась, маскируя секреты. `--help` перечисляет флаги.

### Первый администратор

На пустой базе сервер создаёт его сам, а в момент создания один раз
печатает временный пароль уровнем `warning`:

```
Generated a temporary password for bootstrap administrator "admin": <...>
— it must be changed at first login.
```

Больше этот пароль нигде не появится, так что строку нельзя пропустить.
Задайте `STRUCTURED_LOG_BOOTSTRAP_ADMIN_PASSWORD`, чтобы выбрать пароль
самому — тогда ничего не печатается; либо отключите автосоздание
(`--no-bootstrap-admin-enabled`) и воспользуйтесь
`dart run bin/server.dart create-admin`.

В любом случае учётная запись создаётся с `must_change_password`, и все
эндпоинты, кроме смены пароля, отвечают `403 must_change_password`, пока
флаг не снят.

### Запуск с PostgreSQL

Всё сказанное выше точно так же работает и с PostgreSQL — вместо `--db-path`
задайте `--db-backend=postgres` и настройки подключения, остальной текст
этого README не меняется:

```bash
export STRUCTURED_LOG_JWT_SECRET="$(openssl rand -base64 48 | tr -d '\n')"
export STRUCTURED_LOG_DB_POSTGRES_PASSWORD='...'
dart run bin/server.dart serve \
  --db-backend=postgres \
  --db-postgres-host=localhost --db-postgres-database=structured_log \
  --db-postgres-username=structured_log
```

Backend выбирается один раз, при развёртывании на пустой базе: переключить
его на работающем сервере нельзя, и автоматической миграции SQLite→PostgreSQL нет. Полный список Postgres-специфичных настроек (размер
пула, режим TLS) —
[docs/operations/configuration.ru.md](../../docs/operations/configuration.ru.md#postgresql),
а что именно различается между двумя backend'ами —
[docs/architecture/data-model.ru.md](../../docs/architecture/data-model.ru.md#postgresql-выбираемый-оператором-альтернативный-backend).

## Путь до первой записи

```bash
BASE=http://localhost:8080

# 1. Вход. Form-encoded, в форме RFC 6749.
TOKEN=$(curl -s -X POST $BASE/v1/auth/token \
  -d 'grant_type=password&username=admin&password=<временный>' \
  | jq -r .access_token)

# 2. Снять временный пароль.
curl -s -X POST $BASE/v1/auth/change-password \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"current_password": "<временный>", "new_password": "<новый>"}'
TOKEN=$(curl -s -X POST $BASE/v1/auth/token \
  -d 'grant_type=password&username=admin&password=<новый>' | jq -r .access_token)

# 3. Группа владеет проектами.
GROUP=$(curl -s -X POST $BASE/v1/groups \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"name": "payments"}' | jq -r .id)

# 4. Квота живёт на проекте. retention_days обязателен.
PROJECT=$(curl -s -X POST $BASE/v1/groups/$GROUP/projects \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"name": "checkout", "retention_days": 30, "max_entries": 1000000}' \
  | jq -r .id)

# 5. Секретный ключ аутентифицирует приём. Показывается ровно один раз.
KEY=$(curl -s -X POST $BASE/v1/projects/$PROJECT/secret-keys \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"label": "prod"}' | jq -r .secret)

# 6. Отправить запись ключом...
curl -s -X POST $BASE/v1/logs \
  -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' \
  -d '[{"event": "checkout_started", "level": "info",
        "timestamp": "'"$(date -u +%FT%TZ)"'", "order_id": 42}]'

# 7. ...и прочитать её access-токеном.
curl -s "$BASE/v1/logs?project_id=$PROJECT" -H "Authorization: Bearer $TOKEN"
```

Из приложения вместо `curl` используйте
[`structured_log_remote_sync`](../../emb/structured_log_remote_sync): он собирает записи в батчи,
повторяет отправку при сбоях и не задерживает код, который пишет в лог.

## Как читать аудит

Каждое административное действие и каждая попытка входа попадают в журнал, и
`GET /v1/audit-log` — единственный способ их прочитать. Доступ есть только у
глобального администратора: журнал охватывает всех тенантов, поэтому
урезанного представления, которое было бы безопасно показать владельцу
группы, не бывает — и сервер его не предлагает.

```bash
curl -s -H "Authorization: Bearer $ADMIN_TOKEN" \
  'http://localhost:8080/v1/audit-log?action=auth.login_failed&limit=50'
```

Фильтры (`actor_user_id`, `action`, `target_type`, `target_id`, `from`, `to`)
комбинируются; страницы листаются через `cursor`, в который передаётся
`next_cursor` предыдущей страницы. Значение `action` вне опубликованного
набора отклоняется (400), а не возвращает пустую страницу: журнал нужен,
чтобы ответить на вопрос «было ли такое?», и опечатка, которая выглядит как
«ничего не было», — именно тот неверный ответ, которого допускать нельзя.

Двух вещей в журнале нет никогда: значения секретного ключа и имени,
отправленного при неудачном входе под несуществующей учётной записью. Такая
попытка записывается как `unknown_user` без инициатора: в этом поле нередко
оказывается пароль, набранный не туда, а журнал хранится намного дольше, чем
длится такая оплошность.

Удаляет из него записи только очистка по сроку хранения. Эндпоинта, который правит или
убирает запись, нет, и тест следит, чтобы он не появился.

## Два вида учётных данных, один заголовок

Оба передаются как `Authorization: Bearer <...>`, и сервер различает их по
виду значения:

| | Приём логов | Всё остальное |
|---|---|---|
| Креденшел | Секретный ключ проекта, префикс `slk_` | Access-токен (JWT) |
| Кто владеет | Приложение | Человек |
| Идентифицирует | Проект | Пользователя, с ролями |

Если предъявить один там, где нужен другой, сервер ответит `401` — так же,
как если бы креденшела не было вовсе.

## Просмотр логов в реальном времени

```bash
curl -N "$BASE/v1/logs/stream?project_id=$PROJECT&level=warning" \
  -H "Authorization: Bearer $TOKEN"
```

Server-Sent Events с теми же фильтрами, что у `GET /v1/logs`. При
переподключении передайте `since_id=<последний виденный id>` — поток сначала
дошлёт пропущенное, а затем будет присылать новые записи по мере появления,
без повторов. Keep-alive приходит каждые `--sse-heartbeat-interval-seconds`,
и при каждом таком сигнале сервер заново проверяет, что у клиента всё ещё
есть право держать соединение.

## Конфигурация

Каждая настройка — это CLI-флаг, переменная окружения (`STRUCTURED_LOG_` +
имя флага в верхнем snake case) или значение по умолчанию, в таком порядке
приоритета. Секреты — только через окружение.

<!-- config-reference:implemented -->

| Настройка | По умолчанию |
|---|---|
| `--db-backend` | `sqlite` — либо `postgres`, см. выше |
| `--db-path` | обязательна для `serve` при `--db-backend=sqlite` (по умолчанию) |
| `--db-postgres-host` / `-database` / `-username`, `STRUCTURED_LOG_DB_POSTGRES_PASSWORD` | обязательны для `serve` при `--db-backend=postgres` |
| `STRUCTURED_LOG_JWT_SECRET` | обязательна для `serve`; не короче 32 байт |
| `--http-host` / `--http-port` | `0.0.0.0` / `8080` |
| `--max-ingest-body-bytes` | `10485760` |
| `--retention-purge-interval-seconds` | `3600` |
| `--log-level` / `--log-format` / `--log-file` | `info` / `console` / консоль |
| `--rate-limit-*` | включено, 10 токенов, 10/мин, 10000 ключей |
| `--trusted-proxy-hops` | `0` — `X-Forwarded-For` игнорируется |
| `--sse-heartbeat-interval-seconds` | `25` |
| `--max-live-subscriptions-per-user` | `10` (`0` — без ограничения) |
| `--max-live-subscriptions` | `1000` (`0` — без ограничения) |
| `--cors-allowed-origins` | не задан — CORS-заголовков нет ни на одном ответе |
| `--refresh-token-cookie` | `auto` — cookie `HttpOnly`, если `Origin` не перечислен строкой выше |
| `--audit-retention-days` | не задан — записи аудита хранятся бессрочно |
| `--auth-event-retention-days` | не задан — записи `auth.*` хранятся бессрочно |
| `--audit-purge-batch-size` | `500` |
| `--db-read-pool-size` | `2` |

<!-- /config-reference -->

Полный список с описаниями:
[docs/operations/configuration.ru.md](../../docs/operations/configuration.ru.md).

**За обратным прокси** задайте `--trusted-proxy-hops` равным числу прокси
перед сервером. При `0` ограничитель частоты считает по адресу сокета, а за
прокси это адрес самого прокси — все клиенты попали бы в одно общее ведро.

**CORS по умолчанию выключен** — штатное развёртывание ([deploy/](../../deploy))
отдаёт admin-клиент и API с одного origin, которому CORS не нужен. Задавайте
`--cors-allowed-origins` (через запятую) только когда клиент действительно
обслуживается с другого адреса — например, при локальной разработке, когда
клиент запущен против этого сервера на собственном порту; origin вне списка
не получает заголовков независимо от настройки.

**Refresh-токен попадает в браузер в cookie `HttpOnly`**, которую скрипт на
странице прочитать не может — в отличие от `localStorage`, доступного всему,
что выполняется на этом origin. Тело ответа token-эндпоинта по-прежнему несёт
`refresh_token`, поэтому `curl`, скрипты и любой не-браузерный клиент работают
так же, как раньше: cookie дополняет тело ответа, а не заменяет его. `--refresh-token-cookie`
принимает `auto` (по умолчанию: ставится, если `Origin` запроса не перечислен
в `--cors-allowed-origins`), `on` (всегда — для клиента на другом origin того
же site, например `admin.example.com` рядом с `api.example.com`) и `off`.

**Из-за этого TLS становится обязательным для всего, кроме `localhost`**, а без
него всё ломается без единого сообщения об ошибке: у cookie есть флаг `Secure`, по обычному
HTTP браузер молча её выбрасывает, и выглядит это так — вход прошёл, а минут
через пятнадцать снова появляется экран входа. Сервер этого не обнаружит: за прокси он видит
обычный HTTP, чем бы ни пользовался браузер. Терминируйте TLS либо задайте
`--refresh-token-cookie=off`.

## Документация

- [docs/api/http-api.ru.md](../../docs/api/http-api.ru.md) — все эндпоинты и формы
- [docs/api/models.ru.md](../../docs/api/models.ru.md) — JSON-модели
- [docs/api/errors.ru.md](../../docs/api/errors.ru.md) — коды ошибок
- [docs/architecture/](../../docs/architecture/) — auth, RBAC, хранилище, живой поток, квоты
- [openspec/changes/add-structured-log-server/](../../openspec/changes/add-structured-log-server/) — требования и решения

## Разработка

```bash
dart run build_runner build --delete-conflicting-outputs
dart analyze
dart test --exclude-tags integration --exclude-tags postgres   # основной набор
dart test --tags integration                # поднимают реальный процесс
dart test --tags postgres --concurrency=1   # нужен настоящий PostgreSQL
```

Кодогенерация обязательна: `drift`, `freezed`, `json_serializable` и
`shelf_router_generator` порождают код, без которого пакет не компилируется,
и ничего из этого не коммитится.

## Лицензия

MIT — см. [LICENSE](LICENSE).
