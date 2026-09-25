# Справочник HTTP API

*Read in [English](http-api.md).*

Каждый эндпоинт `structured_log_server`: параметры, тела
запроса/ответа, конкретные ошибки, которые может вернуть именно он, и
пример `curl`. Общие формы объектов — в [models.md](models.ru.md);
полный каталог ошибок (общий для всех эндпоинтов) — в
[errors.md](errors.ru.md) — этот документ ссылается на оба, а не
повторяет их на каждый эндпоинт.

Это вспомогательное чтение поверх нормативных спек OpenSpec, не их
замена — оно закрепляет конкретные wire-формы, которые спеки оставляют
абстрактными. Если `specs/*.md` изменится — приоритет у него.

## Пагинация (`log-server-pagination`)

`GET /v1/logs`, `/v1/audit-log`, `/v1/users`, `/v1/groups` и
`/v1/projects` пагинируются одинаково. Каждый принимает необязательные
`limit` и `cursor` и отвечает `{"items": [...], "next_cursor": строка | null}`.

| Параметр | Примечания |
|---|---|
| `limit` | По умолчанию 50, предел 200 — большее значение обслуживается как 200, а не отклоняется. Не положительное целое → `400 invalid_request`. |
| `cursor` | `next_cursor` предыдущего ответа, переданный обратно как есть. Значение, которого сервер не выдавал → `400 invalid_request`. |

Порядок — сначала новые (большой `id` первым); `cursor` продолжает к более
старым, поэтому строка, созданная во время обхода, не сдвигает страницы.
`next_cursor` равен `null` на последней странице — сервер говорит об этом сам,
запрашивать пустую страницу, чтобы найти конец, не нужно. `total` нет:
подсчёт по аудиту и записям стоит дороже, чем страницы того стоят.

Списки, ограниченные размером одной группы или одного проекта — команды,
участники команды, секретные ключи проекта, выдачи ролей, — не пагинируются
и отдаются целиком одним ответом.

> **Ломающее изменение:** `GET /v1/groups` и `GET /v1/projects` раньше
> возвращали все видимые строки, а теперь возвращают первую страницу (50).
> Вызывающий, читавший их целиком, должен идти по `next_cursor`.

Примеры ниже используют `http://localhost:8080` как базовый URL
сервера, и shell-переменные `$ACCESS_TOKEN` (JWT из `POST
/v1/auth/token`) и `$PROJECT_SECRET_KEY` (из `POST
/v1/projects/:id/secret-keys`, с префиксом `slk_`) — подставьте свои.

## Межоригинные запросы (CORS) (`log-server-api`)

По умолчанию выключено — каждый ответ ниже выглядит именно так и без
заголовка `Origin` вообще, и с тем `Origin`, который оператор не назвал
(`--cors-allowed-origins`, по умолчанию не задан; см.
[configuration.md](../operations/configuration.ru.md)). Это то, что
видит развёртывание с единым origin ([deploy/](../../deploy/)), и то,
что видит любой не-браузерный клиент независимо ни от чего.

Когда запрос несёт заголовок `Origin`, точно совпадающий с одним из
настроенных origin (с учётом регистра, без wildcard — тройка
схема/хост/порт, дословно), меняются две вещи:

- **Preflight отвечается раньше всего остального.** `OPTIONS` с
  заголовком `Access-Control-Request-Method` получает `204` сразу —
  раньше ограничения частоты и аутентификации, на **любом** эндпоинте,
  включая приём логов, — с:

  ```text
  Access-Control-Allow-Origin: <совпавший origin>
  Access-Control-Allow-Methods: GET, POST, PATCH, DELETE, OPTIONS
  Access-Control-Allow-Headers: Authorization, Content-Type
  Vary: Origin
  ```

  Эти три значения — фиксированные константы (то, чем API реально
  пользуется), а не эхо того, что браузер спросил в
  `Access-Control-Request-Method`/`-Headers`.

- **К любому другому ответу, успешному или с ошибкой, добавляются два
  заголовка** поверх того, что он уже несёт — `Access-Control-Allow-Origin:
  <совпавший origin>` и `Vary: Origin` — так что браузер может прочитать
  и тело `401`, `403`, `429` или `5xx`, а не только `200`.

`Origin`, не совпавший ни с одним настроенным значением, трактуется
ровно как отсутствие `Origin` — без заголовков CORS и без отдельного
ответа-отказа. Где это стоит относительно ограничения частоты и
аутентификации — см.
[README.md](../architecture/README.ru.md#цепочка-middleware).

## Приём, запрос и живой поток логов (`log-server-api`, `log-server-live-stream`)

Спека:
[specs/log-server-api/spec.md](../../openspec/changes/add-structured-log-server/specs/log-server-api/spec.md),
[specs/log-server-live-stream/spec.md](../../openspec/changes/add-structured-log-server/specs/log-server-live-stream/spec.md).

### `POST /v1/logs`

Auth: `Authorization: Bearer <секретный ключ проекта>` — значение ключа
несёт префикс `slk_`, которым он отличается от access-токена в общем для
обеих схем заголовке. Предъявленный здесь access-токен даёт `401` —
ровно как отсутствующий креденшел.

**Тело запроса:** JSON-массив произвольных объектов записи лога — см.
[models.md#logentry](models.ru.md#logentry). Без обёртки; массив — всё
тело целиком.

Оба напрашивающихся варианта отклоняются с `400 invalid_request` и
`"Request body must be a JSON array."`: обёртка вида
`{"entries": [...]}`, которую приняло бы большинство батчевых API, и
одиночный объект записи, присланный сам по себе, без массива вокруг.
Одну запись оборачивайте в массив из одного элемента. Пустой массив и
пустое тело допустимы — оба считаются нулём записей.

**Ответ `202`:** [Ответ приёма логов](models.ru.md#ответ-приёма-логов)
— всегда `202`, если сам запрос корректно сформирован/аутентифицирован/
в пределах лимита размера, а проект не заблокирован, даже если каждая
запись отклонена; см.
[errors.md](errors.ru.md#частичный-приём-батча-не-считается-ошибкой).

**Ошибки:** `400 invalid_request` (тело не JSON-массив или вообще не
валидный JSON), `401 unauthorized` (неверный/неизвестный/отозванный
ключ), `403 project_blocked`, `413 payload_too_large`. Коды
`validation_error`/`quota_exceeded` на уровне записи сообщаются внутри
тела `202`, не как HTTP-ошибки.

```bash
curl -X POST http://localhost:8080/v1/logs \
  -H "Authorization: Bearer $PROJECT_SECRET_KEY" \
  -H "Content-Type: application/json" \
  -d '[
    {"event": "payment_failed", "level": "error", "timestamp": "2026-03-05T14:29:59.981Z",
     "category": "checkout", "order_id": "ord_44821"},
    {"event": "request_completed", "level": "info", "timestamp": "2026-03-05T14:30:00.100Z"}
  ]'
```

### `GET /v1/logs`

Auth: `Authorization: Bearer <access-token>`.

**Query-параметры:**

| Параметр | Тип | Примечания |
|---|---|---|
| `project_id` **либо** `group_id` | integer | Ровно один обязателен |
| `level` | string | Минимальный уровень (включительно) |
| `category`, `logger` | string | Точное совпадение |
| `from`, `to` | ISO 8601 | Диапазон по `timestamp`. Значение, которое не читается, или значение с несуществующими компонентами (`2026-13-01`, `2026-02-30`) — `400 invalid_request`, а не отброшенный фильтр |
| `session_id`, `request_id`, `connection_generation`, `tool_call_id`, `message_id`, `operation_id` | string | Точное совпадение |
| `q` | string | Полнотекстовый, по `event` и содержимому |
| `context.<key>` | string | Точное совпадение по произвольному полю, например `context.order_id=ord_44821`. Ключ с точками адресует вложенный объект (`context.order.id`). Пустой сегмент в ключе недопустим — `context.`, `context..x`, `context..` и завершающая точка (`context.a.`) отвечают `400 invalid_request` |
| `limit`, `cursor` | | [Пагинация](#пагинация-log-server-pagination) |

**Ответ `200`:** `{"items": [LogEntry], "next_cursor": строка \| null}` — см. [models.md#logentry](models.ru.md#logentry). Без `cursor` — `items` упорядочены сначала новые по `id`; `cursor` продвигает выборку к более ранним записям.

**Ошибки:** `400 invalid_request` (нечитаемые `from`/`to`, `limit`/`cursor` или `context.<key>` с пустым сегментом), `403 forbidden` (нет гранта на область), `403 project_blocked` (только при прямом `project_id` — запрос по `group_id` молча исключает записи заблокированного проекта), `404 not_found` (`project_id`/`group_id` не существует).

```bash
curl -G http://localhost:8080/v1/logs \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -d project_id=7 \
  -d level=warning \
  -d from=2026-03-05T00:00:00Z \
  -d limit=50
```

### `GET /v1/logs/stream`

Auth: `Authorization: Bearer <access-token>`.

**Query-параметры:** те же, что у `GET /v1/logs` выше, плюс `since_id`
(integer, опционален — точка catch-up, см.
[live-streaming.md](../architecture/live-streaming.ru.md#закрытие-зазора-catch-up-по-since_id)).
Без `limit`/`cursor` — это поток, не страница.

**Ответ `200`:** `Content-Type: text/event-stream`; кадры — `id:
<id записи>` / `event: log` / `data: <LogEntry как JSON>`, плюс
периодические keep-alive комментарии `: ping` и возможное терминальное
`event: end` — полное кадрирование — в
[live-streaming.md](../architecture/live-streaming.ru.md).

**Ошибки:** те же, что `GET /v1/logs`, возвращаются обычным
(непотоковым) ответом *до* перехода соединения в потоковый режим —
отклонённая подписка никогда не открывает поток, который затем
выдаёт ошибку.

```bash
curl -N http://localhost:8080/v1/logs/stream \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -G -d project_id=7 -d level=warning
```

### `GET /healthz`

Auth: нет.

**Ответ `200`:** `{"status": "ok"}`.

**Ошибки:** не определены — пока сервер не готов, эндпоинт не отвечает
(отказ соединения/таймаут), а не возвращает статус ошибки.

```bash
curl http://localhost:8080/healthz
```

## Аутентификация и восстановление пароля (`log-server-auth`, `log-server-password-reset`)

Спека:
[specs/log-server-auth/spec.md](../../openspec/changes/add-structured-log-server/specs/log-server-auth/spec.md),
[specs/log-server-password-reset/spec.md](../../openspec/changes/add-structured-log-server/specs/log-server-password-reset/spec.md),
[specs/log-server-email-verification/spec.md](../../openspec/changes/add-structured-log-server/specs/log-server-email-verification/spec.md).
См. [auth.md](../architecture/auth.ru.md).

> **Запланировано, не реализовано:** `POST /v1/auth/register`,
> `POST /v1/auth/verify-email`, `POST /v1/auth/verify-email/resend`,
> `POST /v1/auth/password-reset` и
> `POST /v1/auth/password-reset/confirm` — пять из девяти эндпоинтов
> ниже — часть изначально специфицированного дизайна (ссылки выше), но
> маршрута в работающем сервере у них нет; каждый отмечен отдельно
> ниже. Каждую учётную запись вместо этого создаёт администратор или
> owner группы (`POST /v1/users`), а забытый пароль сбрасывается тем же
> способом (`PATCH /v1/users/:id`) — см.
> [Руководство разработчика](../guides/developer-guide.ru.md#что-не-реализовано).

**Каждый эндпоинт этого раздела ограничен по частоте**
(`log-server-rate-limit`), вместе с `POST /v1/auth/change-password` и
`DELETE /v1/users/me`: отклонённый запрос получает `429
too_many_requests` с заголовком `Retry-After` и *общим* JSON-конвертом —
включая token-эндпоинт, единственное место, где он отступает от формы
RFC 6749 ([errors.md](errors.ru.md#429--единственный-ответ-token-эндпоинта-не-в-rfc-форме)).
`429` означает, что действие не выполнялось: пароль не проверялся, токен
не выпускался, письмо не отправлялось, и учётная запись не заблокирована
([auth.md](../architecture/auth.ru.md#ограничение-частоты-throttling-без-блокировки)).
Списки ошибок ниже не повторяют `429` у каждого эндпоинта.

### `POST /v1/auth/register`

**Запланировано, не реализовано** — см. пометку в начале раздела.

Auth: нет. JSON-тело, **не** form-encoded — в отличие от token-эндпоинта
ниже, этот путь не часть контракта токенов RFC 6749, так что следует
обычному JSON-соглашению остального API.

**Тело запроса:**

| Поле | Тип | Обязательно |
|---|---|---|
| `username` | string | да |
| `password` | string | да |
| `email` | string | да — обязательно именно на этом пути |
| `display_name` | string | нет |

**Ответ `201`:** [User](models.ru.md#user) (ещё без `RoleAssignment`, `email_verified_at: null`). Письмо подтверждения отправляется как побочный эффект — аккаунт не сможет войти через `grant_type=password`, пока не подтвердит его, см. ниже и [auth.md](../architecture/auth.ru.md#подтверждение-email-обязательно-перед-входом-не-опционально).

**Ошибки:** `400 invalid_request` (отсутствует `email`/`username`/`password`), `403 forbidden` (`registrationEnabled = false`), `409 username_taken`, `409 email_taken`.

```bash
curl -X POST http://localhost:8080/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{"username": "alice", "password": "correct-horse-battery-staple", "email": "alice@example.com"}'
```

### `POST /v1/auth/verify-email`

**Запланировано, не реализовано** — см. пометку в начале раздела.

Auth: нет (токен подтверждения — сам креденшел). JSON-тело.

**Тело запроса:** `{"token": "..."}`

**Ответ `200`:** `{}`. Устанавливает `email_verified_at`, после чего `grant_type=password` работает штатно для этого аккаунта.

**Ошибки:** `400 invalid_token` (неизвестный/истёкший/уже использованный токен).

```bash
curl -X POST http://localhost:8080/v1/auth/verify-email \
  -H "Content-Type: application/json" \
  -d '{"token": "a1b2c3..."}'
```

### `POST /v1/auth/verify-email/resend`

**Запланировано, не реализовано** — см. пометку в начале раздела.

Auth: нет. JSON-тело.

**Тело запроса:** `{"email": "..."}`

**Ответ `202`:** `{}` — всегда, независимо от того, зарегистрирован ли email или уже подтверждён (анти-enumeration, тот же паттерн, что `password-reset`).

**Ошибки:** `400 invalid_request` (отсутствует `email`).

```bash
curl -X POST http://localhost:8080/v1/auth/verify-email/resend \
  -H "Content-Type: application/json" \
  -d '{"email": "alice@example.com"}'
```

### `POST /v1/auth/token`

Auth: нет. **Form-encoded** (`application/x-www-form-urlencoded`), RFC
6749 — единственный эндпоинт в этом API, отклоняющийся от общего
JSON-конверта и в запросе, и в ответе об ошибке, ради совместимости с
готовыми OAuth2-клиентами ([auth.md](../architecture/auth.ru.md)).

**Тело запроса (`grant_type=password`):** `grant_type=password&username=...&password=...`

**Тело запроса (`grant_type=refresh_token`):** `grant_type=refresh_token&refresh_token=...`

**Ответ `200`:** [Ответ токена](models.ru.md#ответ-токена).

**Ошибки:** `429 too_many_requests` (общий конверт, см. выше); в остальном все `400`, форма RFC — `invalid_request` (отсутствует поле для данного `grant_type`), `unsupported_grant_type`, `invalid_grant` (неверные креды; неизвестный/истёкший/отозванный refresh-токен; заблокированный пользователь при refresh; неподтверждённый `email` при `grant_type=password` — ответ дополнительно несёт `reason: "email_not_verified"`, см. [errors.md](errors.ru.md#расширение-rfc-конверта-token-эндпоинта-reason)).

```bash
curl -X POST http://localhost:8080/v1/auth/token \
  -d grant_type=password \
  -d username=alice \
  -d password=correct-horse-battery-staple
```

```bash
curl -X POST http://localhost:8080/v1/auth/token \
  -d grant_type=refresh_token \
  -d refresh_token=$REFRESH_TOKEN
```

### `DELETE /v1/auth/token`

Auth: нет (отзываемый refresh-токен — сам креденшел). Form-encoded, RFC 7009.

**Тело запроса:** `refresh_token=...`

**Ответ `200`:** `{}` — всегда, валиден токен или нет (анти-enumeration, [auth.md](../architecture/auth.ru.md)).

**Ошибки:** `400 invalid_request` (форма RFC) только если само поле `refresh_token` отсутствует в теле.

```bash
curl -X DELETE http://localhost:8080/v1/auth/token \
  -d refresh_token=$REFRESH_TOKEN
```

### `POST /v1/auth/password-reset`

**Запланировано, не реализовано** — см. пометку в начале раздела.

Auth: нет. JSON-тело.

**Тело запроса:** `{"email": "..."}`

**Ответ `202`:** `{}` — всегда, независимо от того, зарегистрирован ли email (анти-enumeration).

**Ошибки:** `400 invalid_request` (отсутствует `email`).

```bash
curl -X POST http://localhost:8080/v1/auth/password-reset \
  -H "Content-Type: application/json" \
  -d '{"email": "alice@example.com"}'
```

### `POST /v1/auth/password-reset/confirm`

**Запланировано, не реализовано** — см. пометку в начале раздела.

Auth: нет (токен восстановления — сам креденшел). JSON-тело.

**Тело запроса:** `{"token": "...", "new_password": "..."}`

**Ответ `200`:** `{}`.

**Ошибки:** `400 invalid_token` (неизвестный/истёкший/уже использованный токен), `400 invalid_request` (отсутствует поле).

```bash
curl -X POST http://localhost:8080/v1/auth/password-reset/confirm \
  -H "Content-Type: application/json" \
  -d '{"token": "a1b2c3...", "new_password": "even-better-passphrase"}'
```

### `DELETE /v1/users/me`

Auth: `Authorization: Bearer <access-token>`. JSON-тело.

**Тело запроса:** `{"password": "..."}`

**Ответ `204`:** пустое тело.

**Ошибки:** `401 invalid_grant` (неверный пароль), `403 cannot_delete_primary_admin`, `409 sole_group_owner` (`details.blocking_groups`).

```bash
curl -X DELETE http://localhost:8080/v1/users/me \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"password": "correct-horse-battery-staple"}'
```

### `POST /v1/auth/change-password`

Auth: `Authorization: Bearer <access-token>`. JSON-тело. Доступен любой
аутентифицированной роли, только над собственной учётной записью — не
только пока установлен `must_change_password`
(`log-server-forced-password-change`,
[auth.md](../architecture/auth.ru.md#patch-v1usersid-и-обязательный-временный-пароль)).

**Тело запроса:** `{"current_password": "...", "new_password": "...", "keep_other_sessions": false, "current_refresh_token": "..."}` — последние два необязательны.

**Ответ `200`:** `{}`. Снимает `must_change_password`, если он был установлен.

Успешная смена, кроме того, завершает **остальные** сессии учётной
записи: отзываются все её refresh-токены, кроме названного в
`current_refresh_token`. Одного инкремента `token_version` для этого не
хватает — он прекращает действие access-токенов, а refresh-токен
переживает его и выдаёт новый, так что пароль, сменённый из-за того,
что его кто-то узнал, этого человека не выгонит.

Безопасное поведение — поведение по умолчанию, поэтому клиент, не
приславший ни одного из двух полей, получает отзыв. Значит, и
вызывающий, не назвавший своего токена, выходит вместе со всеми: другого
способа опознать спрашивающую сессию у сервера нет — эндпоинт
аутентифицируется *access*-токеном, а хранимые refresh-токены
представлены хэшами и ничего не говорят о том, чьё это устройство.
Чтобы остаться в системе, присылайте `current_refresh_token`; чтобы не
трогать ни одну сессию — `keep_other_sessions: true`.

**Ошибки:** `401 invalid_grant` (неверный текущий пароль); `400 invalid_request`, если `new_password` короче 8 символов (`details.reason: "too_short"`, `min_length`) или длиннее 72 байт в UTF-8 (`"too_long"`, `max_bytes`) — то же правило действует везде, где пароль задаётся (`POST /v1/users`, `PATCH /v1/users/:id`). Проверяется при *выборе* пароля, но никогда при входе. `400 invalid_request` с `details.field`, называющим поле, если `keep_other_sessions` не boolean или `current_refresh_token` не строка.

```bash
curl -X POST http://localhost:8080/v1/auth/change-password \
  -H "Authorization: Bearer $ACCESS_TOKEN" -H "Content-Type: application/json" \
  -d '{"current_password": "temp-password-123", "new_password": "a-much-better-passphrase",
       "current_refresh_token": "'"$REFRESH_TOKEN"'"}'
```

## Пользователи, группы, команды, роли (`log-server-rbac`)

Спека:
[specs/log-server-rbac/spec.md](../../openspec/changes/add-structured-log-server/specs/log-server-rbac/spec.md),
[specs/log-server-forced-password-change/spec.md](../../openspec/changes/add-structured-log-server/specs/log-server-forced-password-change/spec.md).
См. [rbac-and-lifecycle.md](../architecture/rbac-and-lifecycle.ru.md).
Все эндпоинты ниже: `Authorization: Bearer <access-token>`, JSON-тела.

### `POST /v1/users`

Роль: `admin`.

**Тело запроса:** те же поля, что `POST /v1/auth/register`, но `email` здесь опционален.

**Ответ `201`:** [User](models.ru.md#user) — `must_change_password: true` всегда (`log-server-forced-password-change`); `email_verified_at: null`, если `email` был указан.

**Ошибки:** `400 invalid_request` (нет username/password либо пароль вне диапазона 8 символов – 72 байта, `details.reason` `too_short`/`too_long`), `403 forbidden`, `409 username_taken`, `409 email_taken`.

```bash
curl -X POST http://localhost:8080/v1/users \
  -H "Authorization: Bearer $ACCESS_TOKEN" -H "Content-Type: application/json" \
  -d '{"username": "bob", "password": "temp-password-123", "display_name": "Bob Diaz"}'
```

### `GET /v1/users`

Роль: `admin`.

**Query:** `username` (подстрока), `limit`, `cursor` — см. [Пагинацию](#пагинация-log-server-pagination).

**Ответ `200`:** `{"items": [User], "next_cursor": строка \| null}`.

**Ошибки:** `403 forbidden`.

```bash
curl -G http://localhost:8080/v1/users -H "Authorization: Bearer $ACCESS_TOKEN" -d limit=50
```

### `PATCH /v1/users/:id`

Роль: `admin`. Частичное обновление — любое подмножество полей ниже.

**Тело запроса:**

| Поле | Тип | Примечания |
|---|---|---|
| `email` | string | Новое значение сбрасывает `email_verified_at` в `null` и запускает новое письмо подтверждения |
| `display_name` | string | |
| `password` | string | Установка этого поля всегда ставит `must_change_password: true` и отзывает все refresh-токены цели |

**Ответ `200`:** [User](models.ru.md#user) (обновлённый).

**Ошибки:** `403 forbidden`, `404 not_found`, `409 email_taken`.

```bash
curl -X PATCH http://localhost:8080/v1/users/42 \
  -H "Authorization: Bearer $ACCESS_TOKEN" -H "Content-Type: application/json" \
  -d '{"password": "new-temp-password-456"}'
```

### `POST /v1/users/:id/block` / `POST /v1/users/:id/unblock`

Роль: `admin`. Без тела запроса.

**Ответ `200`:** [User](models.ru.md#user) (с обновлённым `is_active`).

**Ошибки:** `403 forbidden`, `404 not_found`; дополнительно у `unblock`: `409 deleted_account`.

```bash
curl -X POST http://localhost:8080/v1/users/42/block -H "Authorization: Bearer $ACCESS_TOKEN"
curl -X POST http://localhost:8080/v1/users/42/unblock -H "Authorization: Bearer $ACCESS_TOKEN"
```

### `DELETE /v1/users/:id`

Роль: `admin`. Без тела запроса — пароль цели никогда не требуется.

**Ответ `204`:** пустое тело.

**Ошибки:** `400 self_deletion_requires_me` (`:id == вызывающий`), `403 forbidden`, `403 cannot_delete_primary_admin`, `404 not_found`, `409 sole_group_owner`.

```bash
curl -X DELETE http://localhost:8080/v1/users/99 -H "Authorization: Bearer $ACCESS_TOKEN"
```

### `POST /v1/groups`

Роль: `admin`.

**Тело запроса:** `{"name": "..."}`

**Ответ `201`:** [Group](models.ru.md#group).

**Ошибки:** `403 forbidden`.

```bash
curl -X POST http://localhost:8080/v1/groups \
  -H "Authorization: Bearer $ACCESS_TOKEN" -H "Content-Type: application/json" \
  -d '{"name": "payments-team"}'
```

### `GET /v1/groups`

Роль: любой аутентифицированный пользователь; результат ограничен видимыми группами.
Видимость входит в сам запрос, поэтому вызывающий с одной группой среди тысячи
получает её на первой странице.

**Query:** `name` (подстрока, без учёта регистра), `limit`, `cursor` — см. [Пагинацию](#пагинация-log-server-pagination).

**Ответ `200`:** `{"items": [Group], "next_cursor": строка \| null}`.

```bash
curl http://localhost:8080/v1/groups -H "Authorization: Bearer $ACCESS_TOKEN"
```

### `POST /v1/groups/:groupId/teams`

Роль: `owner` группы `:groupId`, или `admin`.

**Тело запроса:** `{"name": "..."}`

**Ответ `201`:** [Team](models.ru.md#team).

**Ошибки:** `403 forbidden`, `404 not_found` (`:groupId`).

```bash
curl -X POST http://localhost:8080/v1/groups/3/teams \
  -H "Authorization: Bearer $ACCESS_TOKEN" -H "Content-Type: application/json" \
  -d '{"name": "on-call"}'
```

### `GET /v1/groups/:groupId/teams`

Роль: любая роль с доступом на чтение к `:groupId` (`admin`/`owner`/`user`).

**Ответ `200`:** `{"items": [Team]}`.

**Ошибки:** `403 forbidden`, `404 not_found` (`:groupId`).

```bash
curl http://localhost:8080/v1/groups/3/teams -H "Authorization: Bearer $ACCESS_TOKEN"
```

### `GET /v1/teams/:teamId/members`

Роль: та же, что выше. Минимальная форма, не полный
[User](models.ru.md#user) — только то, что нужно, чтобы показать участника и
выбрать его: `{"items": [{"user_id": 42, "username": "alice"}]}`.

**Ошибки:** `403 forbidden`, `404 not_found` (`:teamId`).

```bash
curl http://localhost:8080/v1/teams/5/members -H "Authorization: Bearer $ACCESS_TOKEN"
```

### `POST /v1/teams/:teamId/members`

Роль: `owner` группы этой команды, или `admin`. Инкрементирует
`token_version` только у добавленного пользователя, не у остальных участников
команды — их собственный доступ не меняется от того, что в команду вошёл
кто-то ещё
([auth.md](../architecture/auth.ru.md#token_version-как-снапшот-в-jwt-остаётся-отзываемым)).

**Тело запроса:** `{"user_id": 42}`

**Ответ `204`:** пустое тело.

**Ошибки:** `403 forbidden`, `404 not_found` (`:teamId` или `user_id`).

```bash
curl -X POST http://localhost:8080/v1/teams/5/members \
  -H "Authorization: Bearer $ACCESS_TOKEN" -H "Content-Type: application/json" \
  -d '{"user_id": 42}'
```

### `DELETE /v1/teams/:teamId/members/:userId`

Роль: `owner` группы этой команды, или `admin`. Инкрементирует
`token_version` только у удалённого пользователя — тот же одиночный эффект,
что выше, применённый к тому, кто только что потерял доступ.

**Ответ `204`:** пустое тело.

**Ошибки:** `403 forbidden`, `404 not_found`, `409 sole_group_owner` (участник — последний в команде, владеющей группой, и больше никто ею не владеет — `details.blocking_groups`).

```bash
curl -X DELETE http://localhost:8080/v1/teams/5/members/42 -H "Authorization: Bearer $ACCESS_TOKEN"
```

### `POST /v1/role-assignments`

Роль: `admin` (любой грант), или `owner` (`owner`/`user` только в рамках своей группы/её проектов).

**Тело запроса:**

| Поле | Тип | Примечания |
|---|---|---|
| `subject_type` | `"user"` \| `"team"` | |
| `subject_id` | integer | |
| `role` | `"admin"` \| `"owner"` \| `"user"` | |
| `scope_type` | `"global"` \| `"group"` \| `"project"` | |
| `scope_id` | integer | Обязателен, если не `scope_type: "global"` |

**Ответ `201`:** [RoleAssignment](models.ru.md#roleassignment).

**Ошибки:** `400 invalid_request`, `403 forbidden` (включая попытку `owner` выдать `role: admin`, или область вне своей группы), `404 not_found` (`subject_id`/`scope_id`).

```bash
curl -X POST http://localhost:8080/v1/role-assignments \
  -H "Authorization: Bearer $ACCESS_TOKEN" -H "Content-Type: application/json" \
  -d '{"subject_type": "user", "subject_id": 42, "role": "user", "scope_type": "project", "scope_id": 7}'
```

### `DELETE /v1/role-assignments/:id`

Роль: то же правило, что при создании.

**Ответ `204`:** пустое тело.

**Ошибки:** `403 forbidden`, `404 not_found`, `409 sole_group_owner` (отзыв последнего гранта `owner` на группе — `details.blocking_groups`).

```bash
curl -X DELETE http://localhost:8080/v1/role-assignments/128 -H "Authorization: Bearer $ACCESS_TOKEN"
```

## Проекты и квоты (`log-server-rbac`, `log-server-quotas`)

Спека:
[specs/log-server-quotas/spec.md](../../openspec/changes/add-structured-log-server/specs/log-server-quotas/spec.md).
См. [quotas-and-audit.md](../architecture/quotas-and-audit.ru.md). Все
эндпоинты: `Authorization: Bearer <access-token>`, JSON-тела.

### `GET /v1/projects`

Роль: любой аутентифицированный пользователь; все проекты, которые вызывающий
вправе читать, плоским списком — роль на проект не покрывает его группу, и для
такого пользователя это единственный способ его найти.

**Query:** `group_id`, `name` (подстрока, без учёта регистра), `limit`, `cursor` — см. [Пагинацию](#пагинация-log-server-pagination).

**Ответ `200`:** `{"items": [Project], "next_cursor": строка \| null}`. Несёт `is_blocked`, но не счётчики использования — они у `GET /v1/projects/:id`.

```bash
curl -G http://localhost:8080/v1/projects -H "Authorization: Bearer $ACCESS_TOKEN" -d limit=50
```

### `POST /v1/groups/:groupId/projects`

Роль: `owner` группы `:groupId`, или `admin`.

**Тело запроса:**

| Поле | Тип | Обязательно |
|---|---|---|
| `name` | string | да |
| `retention_days` | integer | да |
| `max_entries` | integer | нет |
| `max_bytes` | integer | нет |

**Ответ `201`:** [Project](models.ru.md#project) (без `entry_count`/`total_bytes`).

**Ошибки:** `400 invalid_request` (отсутствует `retention_days`), `403 forbidden`, `404 not_found` (`:groupId`).

```bash
curl -X POST http://localhost:8080/v1/groups/3/projects \
  -H "Authorization: Bearer $ACCESS_TOKEN" -H "Content-Type: application/json" \
  -d '{"name": "checkout-service", "retention_days": 30, "max_entries": 1000000}'
```

### `PATCH /v1/projects/:id`

Роль: `owner`/`admin`.

**Тело запроса:** любое из `retention_days`/`max_entries`/`max_bytes` (частичное обновление).

**Ответ `200`:** [Project](models.ru.md#project) (обновлённый, без `entry_count`/`total_bytes`).

**Ошибки:** `403 forbidden`, `404 not_found`.

```bash
curl -X PATCH http://localhost:8080/v1/projects/7 \
  -H "Authorization: Bearer $ACCESS_TOKEN" -H "Content-Type: application/json" \
  -d '{"max_entries": 2000000}'
```

### `GET /v1/projects/:id`

Роль: `owner`/`user` с доступом, или `admin`.

**Ответ `200`:** [Project](models.ru.md#project), **с** `entry_count`/`total_bytes`.

**Ошибки:** `403 forbidden`, `404 not_found`.

```bash
curl http://localhost:8080/v1/projects/7 -H "Authorization: Bearer $ACCESS_TOKEN"
```

### `POST /v1/projects/:id/block` / `POST /v1/projects/:id/unblock`

Роль: только `admin` — не `owner`, даже для собственного проекта. Без тела запроса.

**Ответ `200`:** [Project](models.ru.md#project) (с обновлённым `is_blocked`).

**Ошибки:** `403 forbidden`, `404 not_found`.

```bash
curl -X POST http://localhost:8080/v1/projects/7/block -H "Authorization: Bearer $ACCESS_TOKEN"
curl -X POST http://localhost:8080/v1/projects/7/unblock -H "Authorization: Bearer $ACCESS_TOKEN"
```

### `POST /v1/projects/:id/secret-keys`

Роль: `owner`/`admin`.

**Тело запроса:** `{"label": "..."}` (опционально).

**Ответ `201`:** [ProjectSecretKey](models.ru.md#projectsecretkey), **с** `secret` — показывается ровно этот единственный раз.

**Ошибки:** `403 forbidden`, `404 not_found`.

```bash
curl -X POST http://localhost:8080/v1/projects/7/secret-keys \
  -H "Authorization: Bearer $ACCESS_TOKEN" -H "Content-Type: application/json" \
  -d '{"label": "prod-checkout-instance-1"}'
```

### `GET /v1/projects/:id/secret-keys`

Роль: `owner`/`user` с доступом, или `admin`.

**Ответ `200`:** `{"items": [ProjectSecretKey]}` — только метаданные, никогда `secret`.

**Ошибки:** `403 forbidden`, `404 not_found`.

```bash
curl http://localhost:8080/v1/projects/7/secret-keys -H "Authorization: Bearer $ACCESS_TOKEN"
```

### `DELETE /v1/projects/:id/secret-keys/:keyId`

Роль: `owner`/`admin`. Необратимо.

**Ответ `204`:** пустое тело.

**Ошибки:** `403 forbidden`, `404 not_found`.

```bash
curl -X DELETE http://localhost:8080/v1/projects/7/secret-keys/15 -H "Authorization: Bearer $ACCESS_TOKEN"
```

## Аудит-лог (`log-server-audit`)

Спека:
[specs/log-server-audit/spec.md](../../openspec/changes/add-structured-log-server/specs/log-server-audit/spec.md).
См. [quotas-and-audit.md](../architecture/quotas-and-audit.ru.md#аудит-лог-log-server-audit).

### `GET /v1/audit-log`

Auth: `Authorization: Bearer <access-token>`. Роль: только `admin`.

**Query-параметры:** `actor_user_id`, `action`, `target_type`, `target_id`, `from`, `to`, `limit`, `cursor`. Неизвестный `action` и нечитаемые `from`/`to` дают `400 invalid_request`, а не пустую страницу: в журнале, отвечающем на вопрос «было ли это», «записей нет» и «вы опечатались» не должны выглядеть одинаково.

**Ответ `200`:** `{"items": [AuditLogEntry], "next_cursor": string \| null, "audit_retention_days": integer \| null, "auth_event_retention_days": integer \| null}` — два поля срока хранения сообщают действующую политику (`null` = хранится без ограничения срока), поэтому пустой результат за её пределами объясняет сам себя ([quotas-and-audit.md](../architecture/quotas-and-audit.ru.md#аудит-лог-log-server-audit)).

**Ошибки:** `400 invalid_request` (неизвестный `action`, нечитаемые `from`/`to`, `limit`/`cursor`), `403 forbidden`.

Эндпоинта, удаляющего записи аудита, не существует ни для какой роли, а сроки хранения задаются конфигурацией сервера, а не через API — администратор является субъектом этого журнала, а не его владельцем. Записи исчезают только по настроенной оператором политике, и каждый проход очистки, что-то удаливший, оставляет после себя запись `audit.purged`.

```bash
curl -G http://localhost:8080/v1/audit-log \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -d action=user.blocked \
  -d limit=50
```

## Смотрите также

- [models.md](models.ru.md) — полные формы объектов.
- [errors.md](errors.ru.md) — полный каталог ошибок, включая различие
  между кодами на уровне записи батча и верхнеуровневыми HTTP-ошибками,
  и почему `403` иногда используется вместо `404`.
- [configuration.md](../operations/configuration.ru.md#справочник) —
  `--cors-allowed-origins` и все остальные настройки.
