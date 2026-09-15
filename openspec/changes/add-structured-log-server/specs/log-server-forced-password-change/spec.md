## ADDED Requirements

### Requirement: Администратор может редактировать email/display_name/пароль существующего пользователя
Сервер SHALL предоставлять `PATCH /v1/users/:id`, принимающий частичное обновление любого подмножества полей `email`, `display_name`, `password` существующего пользователя. Этот эндпоинт SHALL не изменять `username`, `is_active`, `deleted_at`, `is_primary_admin` или роли — у каждого из них есть отдельный эндпоинт с собственной авторизацией.

#### Scenario: Изменение display_name
- **WHEN** `admin` отправляет `PATCH /v1/users/:id` с новым значением `display_name`
- **THEN** сервер сохраняет новое значение, остальные поля пользователя не изменяются

#### Scenario: Изменение email на занятое значение отклоняется
- **WHEN** `admin` отправляет `PATCH /v1/users/:id` с `email`, уже принадлежащим другому пользователю
- **THEN** сервер отвечает 409 `email_taken` и не изменяет запись

#### Scenario: username не может быть изменён этим эндпоинтом
- **WHEN** `PATCH /v1/users/:id` отправлен с полем `username`
- **THEN** сервер игнорирует это поле (или отклоняет запрос как невалидный) — значение `username` не изменяется в любом случае

### Requirement: Смена email через PATCH сбрасывает подтверждение
Если `PATCH /v1/users/:id` изменяет `email` на значение, отличное от предыдущего (включая переход от отсутствующего к заданному или наоборот), сервер SHALL установить `User.email_verified_at = null` и, если новое значение непустое, выпустить новый токен подтверждения тем же путём, что `POST /v1/auth/register`/`POST /v1/users` (`log-server-email-verification`).

#### Scenario: Новый email требует нового подтверждения
- **WHEN** `admin` меняет `email` пользователя, у которого прежний `email` уже был подтверждён (`email_verified_at` был установлен)
- **THEN** `email_verified_at` этого пользователя сбрасывается в `null`, и на новый адрес отправляется токен подтверждения; `grant_type=password` для этого пользователя отклоняется до повторного подтверждения

#### Scenario: Изменение display_name не влияет на подтверждение email
- **WHEN** `PATCH /v1/users/:id` меняет только `display_name`, не затрагивая `email`
- **THEN** `email_verified_at` не изменяется

### Requirement: Пароль, заданный администратором, всегда временный
Если `password` установлен через `POST /v1/users` (`log-server-rbac`), изменён через `PATCH /v1/users/:id` или назначен сервером — при автоматическом создании первого администратора либо командой `create-admin`, запущенной без пароля (`log-server-auth`), сервер SHALL безусловно установить `User.must_change_password = true` (без параметра, позволяющего это отключить) и отозвать все текущие refresh-токены целевого пользователя. Самостоятельная регистрация (`POST /v1/auth/register`) и команда `create-admin`, которой пароль указал оператор, SHALL не устанавливать этот флаг — в обоих случаях пароль выбирает человек, а не сервер. Именно поэтому `create-admin` без пароля — исключение: там пароль выбрал сервер и напечатал его в консоль, то есть выполнено ровно то условие, из-за которого флаг и существует.

#### Scenario: Создание пользователя администратором помечает пароль временным
- **WHEN** `admin` создаёт пользователя через `POST /v1/users`
- **THEN** у созданного пользователя `must_change_password = true`

#### Scenario: Сброс пароля через PATCH помечает его временным и отзывает сессии
- **WHEN** `admin` меняет `password` существующего пользователя через `PATCH /v1/users/:id`
- **THEN** у этого пользователя `must_change_password` становится `true`, и все его ранее выданные refresh-токены становятся отозванными

#### Scenario: Автоматически созданный администратор обязан сменить пароль
- **WHEN** сервер автоматически создал первого администратора при старте на пустой базе
- **THEN** у созданной учётной записи `must_change_password = true`, и после входа любой management-запрос от неё отклоняется, пока пароль не сменён

#### Scenario: create-admin с паролем от оператора не помечает его временным
- **WHEN** администратор создан командой `create-admin`, а пароль указал сам оператор
- **THEN** у созданной учётной записи `must_change_password = false`

#### Scenario: create-admin без пароля помечает сгенерированный временным
- **WHEN** администратор создан командой `create-admin`, запущенной без пароля, и сервер сгенерировал его сам
- **THEN** у созданной учётной записи `must_change_password = true` — пароль, который назначил сервер, временен независимо от того, каким путём учётная запись создана

#### Scenario: Самостоятельная регистрация не помечает пароль временным
- **WHEN** пользователь успешно регистрируется через `POST /v1/auth/register`
- **THEN** у созданного пользователя `must_change_password = false`

### Requirement: Вход с временным паролем разрешён, но не остальные действия
`grant_type=password` SHALL выдавать токены пользователю с `must_change_password = true` так же, как и любому другому — это поле SHALL не влиять на выдачу токена. Пока `User.must_change_password = true`, сервер SHALL отклонять (403, код `must_change_password`, общий JSON-конверт ошибок) любой JWT-аутентифицированный запрос, кроме `POST /v1/auth/change-password`, `DELETE /v1/users/me`, `POST /v1/auth/token` (`grant_type=refresh_token`) и `DELETE /v1/auth/token`.

#### Scenario: Вход с временным паролем выдаёт токены
- **WHEN** пользователь с `must_change_password = true` отправляет `POST /v1/auth/token` с `grant_type=password` и верным (временным) паролем
- **THEN** сервер выдаёт обычную пару токенов, как и для любого другого пользователя

#### Scenario: Прочие запросы отклоняются, пока пароль не сменён
- **WHEN** пользователь с `must_change_password = true` и действительным access-токеном отправляет любой запрос, кроме `POST /v1/auth/change-password`/`DELETE /v1/users/me`/`POST /v1/auth/token` (`refresh_token`)/`DELETE /v1/auth/token` (например, `GET /v1/logs`)
- **THEN** сервер отвечает 403 с кодом `must_change_password`, не выполняя запрошенное действие

#### Scenario: Разрешённые исключения продолжают работать
- **WHEN** пользователь с `must_change_password = true` отправляет `POST /v1/auth/token` с `grant_type=refresh_token`, или `DELETE /v1/auth/token`, или `DELETE /v1/users/me` с верным паролем
- **THEN** сервер обрабатывает запрос штатно, не отклоняя его по причине `must_change_password`

### Requirement: POST /v1/auth/change-password меняет пароль и снимает временный статус
Сервер SHALL предоставлять `POST /v1/auth/change-password` (JSON-тело `{"current_password": "...", "new_password": "..."}"`, доступен любой аутентифицированной роли только над собственной учётной записью), проверяющий `current_password`; при совпадении SHALL обновить `password_hash`, инкрементировать `User.token_version` и установить `User.must_change_password = false`.

#### Scenario: Успешная смена пароля снимает флаг
- **WHEN** пользователь с `must_change_password = true` отправляет `POST /v1/auth/change-password` с верным `current_password` и новым `new_password`
- **THEN** сервер отвечает успехом, `must_change_password` становится `false`, и последующие запросы этого пользователя больше не отклоняются по этой причине

#### Scenario: Неверный текущий пароль отклоняется
- **WHEN** `POST /v1/auth/change-password` отправлен с неверным `current_password`
- **THEN** сервер отвечает 401 `invalid_grant`, пароль не изменяется, `must_change_password` не снимается

#### Scenario: Смена пароля доступна и без временного статуса
- **WHEN** пользователь с `must_change_password = false` отправляет `POST /v1/auth/change-password` с верным текущим паролем
- **THEN** сервер меняет пароль так же, как и для пользователя с временным паролем — этот эндпоинт не ограничен только случаем принудительной смены

### Requirement: Изменение пароля и учётной записи фиксируется в аудите
Успешный `PATCH /v1/users/:id` SHALL создавать аудит-запись `action: user.updated` (`actor_user_id` — вызывающий `admin`, `target_id` — редактируемый пользователь, `metadata` перечисляет изменённые поля, без значения пароля в любой форме). Успешный `POST /v1/auth/change-password` SHALL создавать аудит-запись `action: password.changed` (`actor_user_id` и `target_id` — сам пользователь).

#### Scenario: Аудит-запись редактирования не содержит значение пароля
- **WHEN** `admin` меняет `password` пользователя через `PATCH /v1/users/:id`
- **THEN** создаётся аудит-запись `user.updated`, чья `metadata` отмечает, что поле `password` было изменено, но не содержит ни хэш, ни исходное значение пароля

#### Scenario: Самостоятельная смена пароля фиксируется отдельным действием
- **WHEN** пользователь успешно выполняет `POST /v1/auth/change-password`
- **THEN** создаётся аудит-запись `action: password.changed` с `actor_user_id` и `target_id`, равными этому пользователю — отдельно от `password.reset_confirmed` (`log-server-password-reset`) и от `user.updated`
