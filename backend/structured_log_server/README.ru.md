# structured_log_server

[![CI](https://github.com/pese-git/structured_log/actions/workflows/ci.yml/badge.svg)](https://github.com/pese-git/structured_log/actions/workflows/ci.yml)

*Read in [English](README.md).*

Self-hosted сервер логов для
[`structured_log`](https://pub.dev/packages/structured_log): приложения
отправляют в него записи по HTTP, люди читают их через API запросов и живой
поток.

На pub.dev не публикуется — это сервис, который запускают, а не библиотека,
от которой зависят.

> **Статус: в разработке.** Приём и запрос логов, живой поток, группы,
> проекты, секретные ключи, аутентификация, RBAC, аудит и жизненный цикл
> пользователя (создание/блокировка/удаление, плюс выдача ролей только
> администратором) работают. Команды, полное правило выдачи ролей (когда
> `owner` выдаёт роли в рамках своей группы), самостоятельная регистрация,
> восстановление пароля и подтверждение email специфицированы, но не
> реализованы — что именно есть, видно в
> [tasks.md](../../openspec/changes/add-structured-log-server/tasks.md).

## Что он делает

- **Приём** — `POST /v1/logs`, аутентификация секретным ключом проекта
- **Запрос** — `GET /v1/logs` с фильтрами, пагинацией и полнотекстовым поиском
- **Живой поток** — `GET /v1/logs/stream`, Server-Sent Events с catch-up
- **Мультитенантность** — группы владеют проектами, роли выдаются по областям
- **Управление пользователями** — `admin` создаёт/редактирует/блокирует/
  удаляет учётные записи (`POST`/`GET`/`PATCH`/`DELETE /v1/users`), выдаёт
  роли (`POST`/`DELETE /v1/role-assignments`, на этом этапе только `admin`)
- **Квоты** — лимиты по числу записей и объёму, окно хранения
- **Ограничение частоты** — token bucket на auth-эндпоинтах, по адресу и по субъекту
- **Аудит** — `GET /v1/audit-log`, только администратору: кто что изменил и кто
  пытался войти
- **Хранилище SQLite** — один файл, без внешних сервисов

## Требования

Dart SDK 3.0 или новее. Больше ничего: база — встроенный файл SQLite,
никаких брокеров, кэшей и отдельных инструментов миграции запускать не надо.

## Запуск

```bash
cd backend/structured_log_server
dart pub get
dart run build_runner build --delete-conflicting-outputs   # drift/freezed/router

export STRUCTURED_LOG_JWT_SECRET='длинная-случайная-строка'
dart run bin/server.dart serve --db-path=./logs.sqlite
```

У секрета подписи намеренно нет CLI-флага: секреты приходят из окружения,
где они не оседают ни в истории шелла, ни в списке процессов.

`dart run bin/server.dart --print-config` печатает все действующие настройки
и откуда каждая взялась, маскируя секреты. `--help` перечисляет флаги.

### Первый администратор

На пустой базе сервер создаёт его сам и один раз, в момент создания,
печатает временный пароль уровнем `warning`:

```
Generated a temporary password for bootstrap administrator "admin": <...>
— it must be changed at first login.
```

Другого канала доставки у этого пароля нет, так что его надо перехватить.
Задайте `STRUCTURED_LOG_BOOTSTRAP_ADMIN_PASSWORD`, чтобы выбрать пароль
самому — тогда ничего не печатается; либо отключите автосоздание
(`--no-bootstrap-admin-enabled`) и воспользуйтесь
`dart run bin/server.dart create-admin`.

В любом случае учётная запись создаётся с `must_change_password`, и все
эндпоинты, кроме смены пароля, отвечают `403 must_change_password`, пока
флаг не снят.

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
[`structured_log_http`](../../emb/structured_log_http): он батчит, повторяет
и не блокирует того, кто логировал.

## Как читать аудит

Каждое административное действие и каждая попытка входа попадают в журнал, и
`GET /v1/audit-log` — единственный способ прочитать их обратно. Доступ только
глобальному администратору: журнал охватывает всех тенантов, поэтому
отфильтрованного вида, который было бы безопасно предложить владельцу группы,
не существует — и его нет.

```bash
curl -s -H "Authorization: Bearer $ADMIN_TOKEN" \
  'http://localhost:8080/v1/audit-log?action=auth.login_failed&limit=50'
```

Фильтры (`actor_user_id`, `action`, `target_type`, `target_id`, `from`, `to`)
комбинируются, пагинация — по `cursor`: обратно отдаётся `next_cursor`
предыдущей страницы. Значение `action` вне опубликованного набора отклоняется
с 400, а не отвечается пустой страницей: в журнале, чья работа — отвечать на
вопрос «это происходило?», опечатка, читающаяся как «ничего не было», — ровно
тот неверный ответ, который недопустим.

Двух вещей в журнале нет никогда: значения секретного ключа и имени,
отправленного при неудачном входе под несуществующей учётной записью. Такая
попытка записывается как `unknown_user` без инициатора — отправленная строка
регулярно оказывается паролем, набранным не в том поле, а журнал переживает
эту ошибку.

Ничто, кроме срока хранения, из него не удаляет. Эндпоинта, который правит или
убирает запись, нет, и тест не даёт ему появиться.

## Два креденшела, один заголовок

Оба приезжают как `Authorization: Bearer <...>`, сервер различает их по
форме значения:

| | Приём логов | Всё остальное |
|---|---|---|
| Креденшел | Секретный ключ проекта, префикс `slk_` | Access-токен (JWT) |
| Кто владеет | Приложение | Человек |
| Идентифицирует | Проект | Пользователя, с ролями |

Предъявление одного там, где нужен другой, даёт `401` — ровно как
отсутствующий креденшел.

## Наблюдать за логами вживую

```bash
curl -N "$BASE/v1/logs/stream?project_id=$PROJECT&level=warning" \
  -H "Authorization: Bearer $TOKEN"
```

Server-Sent Events с теми же фильтрами, что у `GET /v1/logs`. При
переподключении передайте `since_id=<последний виденный id>` — поток сначала
доставит пропущенное, а затем продолжит вживую, без дублей. Keep-alive
приходит каждые `--sse-heartbeat-interval-seconds`, и тот же тик заново
проверяет, что вызывающий всё ещё вправе держать соединение.

## Конфигурация

Каждая настройка — это CLI-флаг, переменная окружения (`STRUCTURED_LOG_` +
имя флага в верхнем snake case) или значение по умолчанию, в таком порядке
приоритета. Секреты — только через окружение.

| Настройка | По умолчанию |
|---|---|
| `--db-path` | обязательна для `serve` |
| `STRUCTURED_LOG_JWT_SECRET` | обязательна для `serve` |
| `--http-host` / `--http-port` | `0.0.0.0` / `8080` |
| `--max-ingest-body-bytes` | `10485760` |
| `--retention-purge-interval-seconds` | `3600` |
| `--log-level` / `--log-format` / `--log-file` | `info` / `console` / консоль |
| `--rate-limit-*` | включено, 10 токенов, 10/мин, 10000 ключей |
| `--trusted-proxy-hops` | `0` — `X-Forwarded-For` игнорируется |
| `--sse-heartbeat-interval-seconds` | `25` |
| `--cors-allowed-origins` | не задан — CORS-заголовков нет ни на одном ответе |
| `--audit-retention-days` | не задан — записи аудита хранятся бессрочно |
| `--auth-event-retention-days` | не задан — записи `auth.*` хранятся бессрочно |
| `--audit-purge-batch-size` | `500` |

Полный список с описаниями:
[docs/operations/configuration.ru.md](../../docs/operations/configuration.ru.md).

**За обратным прокси** задайте `--trusted-proxy-hops` равным числу прокси
перед сервером. При `0` ограничитель частоты считает по адресу сокета, а за
прокси это адрес самого прокси — все клиенты разделили бы одно ведро.

**CORS по умолчанию выключен** — штатное развёртывание ([deploy/](../../deploy))
отдаёт admin-клиент и API с одного origin, которому CORS не нужен. Задавайте
`--cors-allowed-origins` (через запятую) только когда клиент действительно
обслуживается с другого адреса — например, при локальной разработке, когда
клиент запущен против этого сервера на собственном порту; origin вне списка
не получает заголовков независимо от настройки.

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
dart test                          # юнит- и интеграционные
dart test --tags integration       # только те, что поднимают реальный процесс
```

Кодогенерация не опциональна: `drift`, `freezed`, `json_serializable` и
`shelf_router_generator` порождают код, без которого пакет не компилируется,
и ничего из этого не коммитится.

## Лицензия

MIT — см. [LICENSE](LICENSE).
