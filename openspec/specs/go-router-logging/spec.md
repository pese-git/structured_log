# go-router-logging Specification

## Purpose
`StructuredLogGoRouter` (`emb/structured_log_go_router`) — запись навигаций, перенаправлений и ошибок маршрутизации `go_router` в `structured_log` (расположение с шаблоном маршрута и предыдущим расположением, маскирование токенов в query и фрагменте). Введена change `add-structured-log-go-router` (архив `openspec/changes/archive/2026-10-01-add-structured-log-go-router/`).

## Requirements
### Requirement: Каждое новое расположение даёт запись route_changed
После `attach(router)` `StructuredLogGoRouter` SHALL писать `route_changed` на расположение, на котором роутер уже стоит, и на каждое следующее новое расположение (`go`, `push`, `pop`). Запись SHALL содержать `location`, `route` (шаблон маршрута), `route_name` (если у маршрута есть имя), `previous_location`/`previous_route` (кроме первой записи; после навигации, исключённой `filter`, — только `previous_route`) и `category` (по умолчанию `navigation`). Уведомление делегата без нового расположения SHALL NOT давать запись. После `detach()` записи SHALL NOT писаться.

#### Scenario: Переход на маршрут с параметром
- **WHEN** роутер стоит на `/`, затем выполнен `go('/users/42')`
- **THEN** записаны два `route_changed`; второй содержит `location: /users/42`, `route: /users/:id`, `route_name: user`, `previous_location: /`

#### Scenario: push и pop
- **WHEN** выполнены `push('/settings')`, затем `pop()`
- **THEN** записаны `route_changed` с `location` `/settings` и затем `/` с `previous_location: /settings`

#### Scenario: Уведомление без нового расположения
- **WHEN** делегат уведомил слушателей, а расположение не изменилось
- **THEN** новой записи нет

#### Scenario: Навигация, исключённая filter
- **WHEN** `filter` отвергает маршрут `/users/:id`, выполнены `go('/users/alice@example.com')` и затем `go('/login')`
- **THEN** записи для `/users/alice@example.com` нет, запись для `/login` содержит `previous_route: /users/:id` и не содержит `previous_location`, и `alice` не встречается ни в одной записи

### Requirement: Перенаправления пишутся через обёртку redirect
Функция, обёрнутая `redirect(...)`, SHALL писать `route_redirected` с `from` и `to`, когда возвращает расположение, отличное от текущего. Ответ и исключения обёрнутой функции SHALL доходить до роутера без изменений; синхронный ответ SHALL оставаться синхронным.

#### Scenario: Синхронный redirect
- **WHEN** обёрнутый redirect для `/settings` возвращает `/login`
- **THEN** роутер показывает `/login`, а `route_redirected` содержит `from: /settings`, `to: /login`

#### Scenario: Redirect бросает исключение
- **WHEN** обёрнутая функция бросает `StateError`
- **THEN** вызывающий получает тот же `StateError`, а записи нет

### Requirement: Ошибки маршрутизации пишутся в обоих режимах go_router
При переходе на расположение без маршрута SHALL писаться `route_error` (уровень по умолчанию `warning`) с `location` и `error` — слушателем, если роутер показывает страницу ошибки, и обёрткой `onException(...)`, если ошибку обрабатывает приложение. Обёрнутый обработчик SHALL вызываться.

#### Scenario: Страница «не найдено»
- **WHEN** роутер с `errorBuilder` получил `go('/nowhere')`
- **THEN** записан `route_error` с `location: /nowhere` и сообщением об ошибке

#### Scenario: onException
- **WHEN** роутер с обёрнутым `onException` получил `go('/nowhere')`
- **THEN** записан `route_error` с `location: /nowhere`, и обработчик приложения вызван

### Requirement: Токены в расположении маскируются
Значения query-параметров из `redactedQueryParameters` (регистронезависимо) SHALL заменяться на `REDACTED` в `location`, `previous_location`, `from`, `to` и в расположениях, которые `go_router` цитирует в тексте ошибки (`error` у `route_error`), — и в query, и во фрагменте вида `a=b`. Фрагмент другого вида и query без таких параметров SHALL оставаться без изменений.

#### Scenario: Токен во фрагменте
- **WHEN** выполнен `go('/login#access_token=secret&state=s')`
- **THEN** `location` содержит фрагмент `access_token=REDACTED&state=s`, и `secret` не встречается ни в одной записи

#### Scenario: Токен в тексте ошибки
- **WHEN** выполнен `go('/nowhere?token=t')` на несуществующее расположение, или перенаправления зациклились на расположениях с `token=t`
- **THEN** `error` у `route_error` содержит `token=REDACTED` и не содержит `token=t`

### Requirement: Логирование не меняет навигацию
Исключение из `filter` или логирования SHALL NOT выходить из слушателя; навигация SHALL завершаться как без логирования.

#### Scenario: Бросающий фильтр
- **WHEN** `filter` бросает исключение и выполнен `go('/settings')`
- **THEN** роутер показывает `/settings`, записи нет

