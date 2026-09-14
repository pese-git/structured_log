# Модели данных

*Read in [English](models.md).*

Формы JSON-объектов, на которые ссылается [http-api.md](http-api.ru.md).
Это не дословные цитаты из `specs/*.md` — требования OpenSpec намеренно
описывают *поведение* («JSON-объект, идентифицирующий ошибку»), не
всегда фиксируя точные имена полей, поэтому этот документ закрепляет
одну конкретную, согласованную форму для всех них, следуя именам полей
и семантике, уже зафиксированным в
[design.md](../../openspec/changes/add-structured-log-server/design.md)
и [data-model.md](../architecture/data-model.ru.md) там, где они есть.
Если будущая ревизия `specs/*.md` зафиксирует конфликтующую форму —
приоритет у неё, и этот документ следует поправить.

## Соглашения

- Временные метки — строки ISO 8601 в UTC (`2026-03-05T14:30:00.000Z`).
- Каждый эндпоинт списка возвращает `{"items": [...], "next_cursor": "<строка, nullable>"}"`; передайте `next_cursor` обратно как есть параметром запроса `cursor`, чтобы получить следующую страницу. `next_cursor: null` означает, что следующей страницы нет.
- `null` в поле означает «присутствует, но пусто»; отсутствие поля — что оно вообще не задавалось. В запросах опциональные поля можно полностью опускать.
- Ни одна из этих форм никогда не включает хэш пароля, хэш секретного ключа или хэш refresh-токена — они никогда не покидают сервер ни в одном ответе.

## User

Возвращается `POST /v1/auth/register`, `POST /v1/users`, `GET /v1/users`, `POST /v1/users/:id/block`/`unblock`.

| Поле | Тип | Примечания |
|---|---|---|
| `id` | integer | |
| `username` | string | Уникален; идентификатор для входа ([auth.md](../architecture/auth.ru.md)) |
| `display_name` | string \| null | |
| `email` | string \| null | Только контакт для восстановления, не идентификатор для входа |
| `email_verified_at` | string \| null | ISO 8601; `null` блокирует `grant_type=password` для этого аккаунта, если `email` задан ([auth.md](../architecture/auth.ru.md#подтверждение-email-обязательно-перед-входом-не-опционально)); всегда `null`, если `email` — `null` |
| `is_active` | boolean | `false` при блокировке ([rbac-and-lifecycle.md](../architecture/rbac-and-lifecycle.ru.md)) |
| `deleted_at` | string \| null | ISO 8601; устанавливается один раз, никогда не снимается |
| `is_primary_admin` | boolean | `true` не более чем у одного пользователя за всю историю |
| `created_at` | string | ISO 8601 |

```json
{
  "id": 42,
  "username": "alice",
  "display_name": "Alice Chen",
  "email": "alice@example.com",
  "email_verified_at": null,
  "is_active": true,
  "deleted_at": null,
  "is_primary_admin": false,
  "created_at": "2026-01-10T09:00:00.000Z"
}
```

## Group

| Поле | Тип | Примечания |
|---|---|---|
| `id` | integer | |
| `name` | string | |
| `created_at` | string | ISO 8601 |

## Team

| Поле | Тип | Примечания |
|---|---|---|
| `id` | integer | |
| `group_id` | integer | Ровно одна владеющая группа |
| `name` | string | |
| `created_at` | string | ISO 8601 |

## Project

Возвращается `POST /v1/groups/:groupId/projects`, `PATCH /v1/projects/:id`, `GET /v1/projects/:id`, `POST /v1/projects/:id/block`/`unblock`. `GET /v1/projects/:id` дополнительно включает `entry_count`/`total_bytes` (decision 22, [quotas-and-audit.md](../architecture/quotas-and-audit.ru.md)); остальные эндпоинты выше их не включают (не поддерживаются/не запрашиваются вне пути чтения одного проекта).

| Поле | Тип | Примечания |
|---|---|---|
| `id` | integer | |
| `group_id` | integer | |
| `name` | string | |
| `retention_days` | integer | Обязательно |
| `max_entries` | integer \| null | `null` = без лимита |
| `max_bytes` | integer \| null | `null` = без лимита |
| `is_blocked` | boolean | |
| `created_at` | string | ISO 8601 |
| `entry_count` | integer | **Только `GET /v1/projects/:id`** |
| `total_bytes` | integer | **Только `GET /v1/projects/:id`** |

```json
{
  "id": 7,
  "group_id": 3,
  "name": "checkout-service",
  "retention_days": 30,
  "max_entries": 1000000,
  "max_bytes": null,
  "is_blocked": false,
  "created_at": "2026-01-12T11:00:00.000Z",
  "entry_count": 842317,
  "total_bytes": 512048221
}
```

## ProjectSecretKey

Метаданные никогда не включают значение ключа в открытом виде,
**кроме** ответа `POST /v1/projects/:id/secret-keys`, который несёт
`secret` ровно один раз — впоследствии он не извлекаем ни одним
эндпоинтом.

| Поле | Тип | Примечания |
|---|---|---|
| `id` | integer | |
| `project_id` | integer | |
| `label` | string \| null | |
| `created_at` | string | ISO 8601 |
| `revoked_at` | string \| null | |
| `secret` | string | **Только в ответе на создание** — значение в открытом виде, показывается один раз |

## RoleAssignment

| Поле | Тип | Примечания |
|---|---|---|
| `id` | integer | |
| `subject_type` | `"user"` \| `"team"` | |
| `subject_id` | integer | |
| `role` | `"admin"` \| `"owner"` \| `"user"` | |
| `scope_type` | `"global"` \| `"group"` \| `"project"` | |
| `scope_id` | integer \| null | `null` тогда и только тогда, когда `scope_type: "global"` |
| `created_at` | string | ISO 8601 |

## LogEntry

Возвращается `GET /v1/logs` и доставляется потоком `GET /v1/logs/stream`
([live-streaming.md](../architecture/live-streaming.ru.md)). Отдельной
«обёртки context» нет — ответ это тот же самый JSON-объект, который
клиент отправил в `POST /v1/logs` (см. ниже), объединённый с тремя
полями, назначенными сервером, с сохранением любых произвольных полей
(гарантия «полное исходное содержимое» `log-server-storage`, см.
[data-model.md](../architecture/data-model.ru.md)).

| Поле | Тип | Примечания |
|---|---|---|
| `id` | integer | Назначается сервером; курсор keyset-пагинации |
| `project_id` | integer | Назначается сервером, из ключа, аутентифицировавшего приём |
| `received_at` | string | Назначается сервером; ISO 8601, независимо от клиентского `timestamp` |
| `event` | string | Как отправлено |
| `level` | string | Как отправлено — одно из `debug`/`info`/`warning`/`error`/`critical` |
| `timestamp` | string | Как отправлено, ISO 8601 |
| `category` | string \| null | Как отправлено, если было |
| `logger` | string \| null | Как отправлено, если было |
| `session_id`, `request_id`, `connection_generation`, `tool_call_id`, `message_id`, `operation_id` | string \| null | Поля корреляции, как отправлены, если были |
| *(любой другой ключ)* | any | Любые произвольные поля `context`, отправленные клиентом, без изменений |

```json
{
  "id": 918273,
  "project_id": 7,
  "received_at": "2026-03-05T14:30:00.412Z",
  "event": "payment_failed",
  "level": "error",
  "timestamp": "2026-03-05T14:29:59.981Z",
  "category": "checkout",
  "logger": "payment.gateway",
  "session_id": "sess_abc123",
  "request_id": "req_xyz789",
  "connection_generation": null,
  "tool_call_id": null,
  "message_id": null,
  "operation_id": null,
  "order_id": "ord_44821",
  "gateway_response_code": "card_declined"
}
```

(`order_id`/`gateway_response_code` выше — произвольные пользовательские
поля, не часть фиксированной схемы, сохранены ровно как отправлены.)

## AuditLogEntry

Возвращается `GET /v1/audit-log` ([quotas-and-audit.md](../architecture/quotas-and-audit.ru.md)).

| Поле | Тип | Примечания |
|---|---|---|
| `id` | integer | |
| `actor_user_id` | integer \| null | `null` только для событий, действительно не имеющих аутентифицированного вызывающего (таких нет в текущем закрытом наборе действий — см. [quotas-and-audit.md](../architecture/quotas-and-audit.ru.md)) |
| `action` | string | Одно из закрытого набора — см. [quotas-and-audit.md](../architecture/quotas-and-audit.ru.md) |
| `target_type` | string | например, `"user"`, `"project"`, `"role_assignment"` |
| `target_id` | integer \| null | |
| `metadata` | object | Форма зависит от `action` — см. примеры ниже |
| `created_at` | string | ISO 8601 |

Примеры `metadata` по действию:

```json
// action: "project.quota_updated"
{"before": {"retention_days": 30, "max_entries": null}, "after": {"retention_days": 30, "max_entries": 1000000}}

// action: "role_assignment.created"
{"role": "owner", "scope_type": "group", "scope_id": 3, "subject_type": "user", "subject_id": 42}

// action: "user.blocked"
{}
```

## Ответ токена

Возвращается `POST /v1/auth/token` (имена полей RFC 6749 §5.1 —
[auth.md](../architecture/auth.ru.md)).

| Поле | Тип | Примечания |
|---|---|---|
| `access_token` | string | JWT, короткоживущий |
| `refresh_token` | string | Непрозрачный, долгоживущий |
| `token_type` | string | Всегда `"Bearer"` |
| `expires_in` | integer | Секунд до истечения `access_token` |
| `refresh_expires_in` | integer | Секунд до истечения `refresh_token` |

## Claims access-токена (декодированный payload JWT)

Не тело ответа — payload `access_token` после декодирования, для
справки при отладке.

| Claim | Тип | Примечания |
|---|---|---|
| `iss` | string | Настроенный идентификатор-издатель сервера |
| `sub` | string | `User.id` |
| `iat` / `exp` | integer | Unix-таймстемпы |
| `jti` | string | Уникальный id токена |
| `preferred_username` | string | |
| `tv` | integer | Снапшот `User.token_version` на момент выдачи — [auth.md](../architecture/auth.ru.md#token_version-как-снапшот-в-jwt-остаётся-отзываемым) |
| `roles` | массив `{role, scope_type, scope_id}` | Снапшот эффективных прав на момент выдачи |

## Ответ приёма логов

Возвращается `POST /v1/logs`, HTTP `202` — **всегда**, даже если каждая
запись в батче отклонена; сам запрос был принят и обработан
запись-за-записью, так что `4xx`/`5xx` неверно отражал бы произошедшее
(см. [errors.md](errors.ru.md#частичный-приём-батча-не-считается-ошибкой)).

| Поле | Тип | Примечания |
|---|---|---|
| `accepted` | integer | Количество сохранённых записей |
| `rejected` | массив `{index, error, message}` | `index` — позиция записи в отправленном массиве (с 0) |

```json
{
  "accepted": 8,
  "rejected": [
    {"index": 3, "error": "validation_error", "message": "level: must be one of debug, info, warning, error, critical"},
    {"index": 7, "error": "quota_exceeded", "message": "project max_entries limit reached"}
  ]
}
```

## Конверт ошибки

В этом API сосуществуют две формы, обе подробно задокументированы в
[errors.md](errors.ru.md) — это указатель, не дубликат:

- Общий JSON-конверт (`log-server-api`), используемый всеми, кроме token-эндпоинта.
- Форма RFC 6749 §5.2, используемая **только** `POST`/`DELETE /v1/auth/token`.
