## ADDED Requirements

### Requirement: Аудит фиксирует закрытый список административных действий
Сервер SHALL записывать аудит-запись (`actor_user_id`, `action`, `target_type`, `target_id`, `metadata`, `created_at`) при каждом выполнении одного из следующих действий: `user.created`, `user.blocked`, `user.unblocked`, `group.created`, `team.created`, `team.member_added`, `team.member_removed`, `project.created`, `project.quota_updated`, `project.blocked`, `project.unblocked`, `secret_key.created`, `secret_key.revoked`, `role_assignment.created`, `role_assignment.revoked`, `password.reset_confirmed`. Аудит-запись SHALL создаваться в той же транзакции, что и само действие — если действие не применяется (откат/ошибка), аудит-запись также не должна сохраниться.

#### Scenario: Выдача роли создаёт аудит-запись
- **WHEN** `admin` или `owner` успешно выполняет `POST /v1/role-assignments`
- **THEN** создаётся аудит-запись с `action: role_assignment.created`, `actor_user_id`, равным вызывающему, `target_type: role_assignment`, `target_id` новой записи и `metadata`, содержащей роль/область/получателя

#### Scenario: Отклонённое действие не создаёт аудит-запись
- **WHEN** запрос на мутирующее действие (например, `POST /v1/role-assignments`) отклонён сервером (403/400/404 и т.п.) и не был применён
- **THEN** аудит-запись для этого действия не создаётся

#### Scenario: Самостоятельная регистрация фиксируется с самим пользователем как инициатором
- **WHEN** пользователь успешно регистрируется через `POST /v1/auth/register`
- **THEN** создаётся аудит-запись `action: user.created` с `actor_user_id`, равным идентификатору только что созданного пользователя, и `target_id`, также равным этому пользователю

#### Scenario: Блокировка пользователя и проекта фиксируется в аудите
- **WHEN** `admin` выполняет `POST /v1/users/:id/block` или `POST /v1/projects/:id/block`
- **THEN** создаётся аудит-запись с соответствующим `action` (`user.blocked` или `project.blocked`), `actor_user_id` — вызывающий `admin`, `target_id` — заблокированный ресурс

### Requirement: Приём и запрос логов не попадают в аудит
Аудит-лог SHALL не содержать записей о выполнении `POST /v1/logs` или `GET /v1/logs` — это бизнес-данные пользовательского приложения, а не административное действие над ресурсами сервиса.

#### Scenario: Массовый приём логов не создаёт аудит-записи
- **WHEN** в проект принято множество батчей через `POST /v1/logs`
- **THEN** ни одна аудит-запись, связанная с этим приёмом, не создаётся, независимо от объёма принятых записей

### Requirement: Просмотр аудита ограничен ролью admin
Сервер SHALL предоставлять `GET /v1/audit-log`, доступный только пользователям с `RoleAssignment(role: admin, scope: global)`; поддерживающий фильтры `actor_user_id`, `action`, `target_type`, `target_id`, `from`/`to` (диапазон по `created_at`), комбинируемые одновременно, и keyset-пагинацию курсором по `id`, тем же паттерном, что `GET /v1/logs` (`log-server-api`).

#### Scenario: owner не имеет доступа к аудиту
- **WHEN** пользователь без роли `admin` (в т.ч. `owner` любой группы) отправляет `GET /v1/audit-log`
- **THEN** сервер отвечает 403 и не возвращает ни одной записи

#### Scenario: Фильтрация по действию и цели
- **WHEN** `admin` отправляет `GET /v1/audit-log?action=project.blocked&target_type=project&target_id=P`
- **THEN** ответ содержит только записи блокировки/разблокировки именно проекта `P`

#### Scenario: Пагинация курсором не пересекается между страницами
- **WHEN** первый запрос `GET /v1/audit-log?limit=50` возвращает курсор следующей страницы, и этот курсор передан в повторном запросе
- **THEN** второй запрос возвращает следующие записи, не пересекающиеся с уже полученными
