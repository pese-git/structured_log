# Справочник HTTP API

*Read in [English](http-api.md).*

Компактный указатель всех эндпоинтов `structured_log_server`,
сгруппированных по capability. Это вспомогательное чтение, не сам
контракт — за точной формой запроса/ответа и всеми сценариями следуйте
ссылке на спеку в каждом разделе. Детали уровня полей — в `specs/`, не
здесь; эта таблица нужна, чтобы не открывать восемь файлов ради общей
картины сразу.

Ответы об ошибках (кроме двух исключений ниже) — JSON-объект,
идентифицирующий тип/причину ошибки — см. требование «Ошибки возвращаются
в структурированном JSON-формате» в
[specs/log-server-api/spec.md](../../openspec/changes/add-structured-log-server/specs/log-server-api/spec.md).

## Приём, запрос и живой поток логов (`log-server-api`, `log-server-live-stream`)

Спека:
[specs/log-server-api/spec.md](../../openspec/changes/add-structured-log-server/specs/log-server-api/spec.md),
[specs/log-server-live-stream/spec.md](../../openspec/changes/add-structured-log-server/specs/log-server-live-stream/spec.md).

| Метод и путь | Auth | Примечания |
|---|---|---|
| `POST /v1/logs` | Секретный ключ проекта | Батч-вставка; частичный приём при ошибке валидации/квоты; `403 project_blocked`, если проект заблокирован |
| `GET /v1/logs` | Access-JWT | Требует ровно один из `project_id`/`group_id`; фильтры: `level`/`category`/`logger`/`from`/`to`/поля корреляции/`q`/`context.*`; keyset-пагинация по `id`, по умолчанию сначала новые (decision 31) |
| `GET /v1/logs/stream` | Access-JWT | Та же область/фильтры, что `GET /v1/logs`, плюс `since_id`; `Content-Type: text/event-stream`; см. [live-streaming.md](../architecture/live-streaming.ru.md) |
| `GET /healthz` | Нет | 200, как только хранилище инициализировано и готово |

## Аутентификация и восстановление пароля (`log-server-auth`, `log-server-password-reset`)

Спека:
[specs/log-server-auth/spec.md](../../openspec/changes/add-structured-log-server/specs/log-server-auth/spec.md),
[specs/log-server-password-reset/spec.md](../../openspec/changes/add-structured-log-server/specs/log-server-password-reset/spec.md).
Полная картина — [auth.md](../architecture/auth.ru.md).

| Метод и путь | Auth | Примечания |
|---|---|---|
| `POST /v1/auth/register` | Нет | Form: `username`/`password`/`email` (обязателен)/`display_name`; только если `registrationEnabled`; создаёт пользователя без `RoleAssignment` |
| `POST /v1/auth/token` | Нет | Form-encoded, RFC 6749; `grant_type=password` или `grant_type=refresh_token`; форма ответа/ошибки — по RFC 6749 §5.1/§5.2, **не** общий JSON-конверт ошибок остального API |
| `DELETE /v1/auth/token` | Нет (refresh-токен в теле) | Form-encoded, RFC 7009; всегда `200`, пустое тело, валиден токен или нет |
| `POST /v1/auth/password-reset` | Нет | JSON `{email}`; всегда `202`, одинаковое тело, независимо от существования email |
| `POST /v1/auth/password-reset/confirm` | Нет (токен восстановления в теле) | JSON `{token, new_password}`; `400 invalid_token`, если истёк/использован/неизвестен |
| `DELETE /v1/users/me` | Access-JWT + пароль в теле | Самоудаление; возможны `403 cannot_delete_primary_admin` / `409 sole_group_owner` |

## Пользователи, группы, команды, роли (`log-server-rbac`)

Спека:
[specs/log-server-rbac/spec.md](../../openspec/changes/add-structured-log-server/specs/log-server-rbac/spec.md).
См. [rbac-and-lifecycle.md](../architecture/rbac-and-lifecycle.ru.md).

| Метод и путь | Требуемая роль | Примечания |
|---|---|---|
| `POST /v1/users` | `admin` | Создание пользователя; `email` здесь опционален (в отличие от самостоятельной регистрации) |
| `GET /v1/users` | `admin` | Список пользователей |
| `POST /v1/users/:id/block` | `admin` | Также отзывает все refresh-токены |
| `POST /v1/users/:id/unblock` | `admin` | `400`, если цель удалена |
| `DELETE /v1/users/:id` | `admin` | `400`, если `:id == self`; возможны `403 cannot_delete_primary_admin` / `409 sole_group_owner` |
| `POST /v1/groups` | `admin` | |
| `GET /v1/groups` | Любой аутентифицированный пользователь | Ограничено видимыми группами |
| `POST /v1/groups/:groupId/teams` | `owner` группы, или `admin` | |
| `POST /v1/teams/:teamId/members` | `owner`/`admin` | Инкрементирует `token_version` всех текущих участников |
| `DELETE /v1/teams/:teamId/members/:userId` | `owner`/`admin` | Аналогично |
| `POST /v1/role-assignments` | `admin` (любой грант) или `owner` (`owner`/`user` в своей группе) | |
| `DELETE /v1/role-assignments/:id` | То же правило | |

## Проекты и квоты (`log-server-rbac`, `log-server-quotas`)

Спека:
[specs/log-server-quotas/spec.md](../../openspec/changes/add-structured-log-server/specs/log-server-quotas/spec.md).
См. [quotas-and-audit.md](../architecture/quotas-and-audit.ru.md).

| Метод и путь | Требуемая роль | Примечания |
|---|---|---|
| `POST /v1/groups/:groupId/projects` | `owner` группы, или `admin` | `retention_days` обязателен |
| `PATCH /v1/projects/:id` | `owner`/`admin` | Редактирование квоты |
| `GET /v1/projects/:id` | `owner`/`user` с доступом/`admin` | Включает `entry_count`/`total_bytes` рядом с настроенной квотой |
| `POST /v1/projects/:id/block` | Только `admin` (не `owner`) | Останавливает и приём, и прямой запрос |
| `POST /v1/projects/:id/unblock` | Только `admin` | |
| `POST /v1/projects/:id/secret-keys` | `owner`/`admin` | Значение ключа в открытом виде — только в ответе на создание |
| `GET /v1/projects/:id/secret-keys` | `owner`/`admin` | Только метаданные |
| `DELETE /v1/projects/:id/secret-keys/:keyId` | `owner`/`admin` | Необратимо |

## Аудит-лог (`log-server-audit`)

Спека:
[specs/log-server-audit/spec.md](../../openspec/changes/add-structured-log-server/specs/log-server-audit/spec.md).
См. [quotas-and-audit.md](../architecture/quotas-and-audit.ru.md#аудит-лог-log-server-audit).

| Метод и путь | Требуемая роль | Примечания |
|---|---|---|
| `GET /v1/audit-log` | Только `admin` (не `owner`) | Фильтры: `actor_user_id`/`action`/`target_type`/`target_id`/`from`/`to`; keyset-пагинация |

## Два осознанных несоответствия

- `POST`/`DELETE /v1/auth/token` и `POST /v1/auth/password-reset*`
  используют form-encoded тела и ошибки в форме RFC вместо обычного
  JSON-конверта этого API — почему это задокументировано как осознанный
  выбор, а не недосмотр — см. [auth.md](../architecture/auth.ru.md).
- `507 Insufficient Storage`, не `413`, сигнализирует отказ по квоте на
  `POST /v1/logs` — `413` зарезервирован за превышением лимита размера
  HTTP-тела. См. [quotas-and-audit.md](../architecture/quotas-and-audit.ru.md).
