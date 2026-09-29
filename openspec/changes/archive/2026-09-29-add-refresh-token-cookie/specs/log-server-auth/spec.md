## MODIFIED Requirements

### Requirement: Единый OAuth2-совместимый token-эндпоинт (RFC 6749)
Сервер SHALL предоставлять `POST /v1/auth/token`, принимающий тело `application/x-www-form-urlencoded` с обязательным полем `grant_type`, различающий два сценария: `grant_type=password` (поля `username`, `password`) и `grant_type=refresh_token` (поле `refresh_token`). При успехе SHALL возвращать JSON-тело со стандартными полями RFC 6749 §5.1: `access_token`, `token_type` (`"Bearer"`), `expires_in`, `refresh_token`, `refresh_expires_in`. Любая ошибка этого эндпоинта (неверные креды, недействительный `grant_type`, недостающее поле) SHALL возвращать тело в формате RFC 6749 §5.2: `{"error": "<invalid_grant|invalid_request|unsupported_grant_type>", "error_description": "..."}` (отказ по причине неподтверждённого email — `log-server-email-verification` — SHALL дополнительно нести нестандартное поле `reason: "email_not_verified"` поверх этой формы) — этот формат применяется к `POST /v1/auth/token` и `DELETE /v1/auth/token`, отдельно от общего JSON-конверта ошибок остального API (`log-server-api`). Оба сценария (`password` и `refresh_token`) SHALL заново резолвить эффективные роли пользователя и текущее значение `token_version` при каждой выдаче — не копировать их из ранее выданного токена.

Кроме того, сервер SHALL — когда размещение refresh-токена в cookie включено для этого запроса (`log-server-config`) — сопровождать успешный ответ заголовком `Set-Cookie`, несущим тот же refresh-токен с атрибутами `HttpOnly`, `Secure`, `SameSite=Strict`, `Path=/v1/auth` и сроком жизни, равным сроку жизни самого токена. Тело ответа SHALL **всегда** содержать `refresh_token`, независимо от того, поставлена cookie или нет: cookie является дополнением к телу, а не заменой ему, чтобы вызывающий, не хранящий cookie (командная строка, скрипт, не-браузерный клиент), работал без изменений.

Успешный ответ SHALL нести дополнительное поле `refresh_token_cookie_set` (boolean), сообщающее, поставил ли сервер cookie этим ответом. Поле SHALL быть единственным, из чего клиент узнаёт режим: клиент SHALL не требовать собственной настройки, чтобы выбрать между хранением токена из тела и опорой на cookie.

При `grant_type=refresh_token` сервер SHALL брать refresh-токен из поля формы, если оно присутствует, и только при его отсутствии — из cookie. Поле формы SHALL иметь приоритет над cookie всегда: поле выражает намерение вызывающего, а cookie подставляется браузером автоматически. Отсутствие и поля, и cookie SHALL отклоняться как `invalid_request`.

#### Scenario: grant_type=password с верными кредами выдаёт пару токенов
- **WHEN** отправлен `POST /v1/auth/token` (form-encoded) с `grant_type=password`, `username` и `password`, совпадающими с активным (`is_active = true`) пользователем
- **THEN** сервер отвечает 200 с телом, содержащим `access_token` (валидная подпись, корректный `sub`), `token_type: "Bearer"`, `expires_in`, `refresh_token`, `refresh_expires_in`

#### Scenario: grant_type=password с неверным паролем отклоняется в формате RFC 6749
- **WHEN** отправлен `POST /v1/auth/token` с `grant_type=password` и неверным паролем для существующего `username`
- **THEN** сервер отвечает 400 (или 401) с телом `{"error": "invalid_grant", ...}` и не выдаёт токены

#### Scenario: grant_type=password для неактивного пользователя отклоняется
- **WHEN** отправлен `POST /v1/auth/token` с `grant_type=password` и корректными кредами пользователя, у которого `is_active = false`
- **THEN** сервер отвечает с телом `{"error": "invalid_grant", ...}` и не выдаёт токены

#### Scenario: grant_type=password для неподтверждённого email отклоняется
- **WHEN** отправлен `POST /v1/auth/token` с `grant_type=password` и корректными кредами пользователя, у которого `email` задан, но не подтверждён (`log-server-email-verification`)
- **THEN** сервер отвечает телом `{"error": "invalid_grant", "reason": "email_not_verified", ...}` и не выдаёт токены

#### Scenario: Неизвестный grant_type отклоняется
- **WHEN** отправлен `POST /v1/auth/token` с `grant_type`, отличным от `password` и `refresh_token`
- **THEN** сервер отвечает с телом `{"error": "unsupported_grant_type", ...}`

#### Scenario: Успешная выдача ставит cookie и всё равно кладёт токен в тело
- **WHEN** размещение в cookie включено для запроса, и `POST /v1/auth/token` с `grant_type=password` успешен
- **THEN** ответ несёт `Set-Cookie` с refresh-токеном и атрибутами `HttpOnly`, `Secure`, `SameSite=Strict`, `Path=/v1/auth`, а тело по-прежнему содержит `refresh_token` и, кроме того, `refresh_token_cookie_set: true`

#### Scenario: Вызывающий без cookie работает как прежде
- **WHEN** размещение в cookie выключено для запроса, и `POST /v1/auth/token` успешен
- **THEN** ответ не несёт `Set-Cookie`, тело содержит `refresh_token` и `refresh_token_cookie_set: false` — то есть в точности сегодняшнее поведение плюс одно информационное поле

#### Scenario: Обновление принимает токен из cookie, когда поля формы нет
- **WHEN** отправлен `POST /v1/auth/token` с `grant_type=refresh_token`, без поля `refresh_token` в теле, но с cookie, несущей действующий refresh-токен
- **THEN** сервер обновляет пару так же, как если бы токен был предъявлен полем формы

#### Scenario: Поле формы выигрывает у cookie
- **WHEN** отправлен `POST /v1/auth/token` с `grant_type=refresh_token`, полем `refresh_token` в теле и одновременно cookie, несущей **другой** действующий refresh-токен
- **THEN** сервер обрабатывает именно токен из поля формы, а токен из cookie остаётся нетронутым

#### Scenario: Ни поля, ни cookie — отказ
- **WHEN** отправлен `POST /v1/auth/token` с `grant_type=refresh_token` без поля `refresh_token` и без cookie
- **THEN** сервер отвечает телом `{"error": "invalid_request", ...}`

### Requirement: grant_type=refresh_token хранится хэшированным и ротируется при использовании
Refresh-токен SHALL храниться на сервере как хэш случайно сгенерированной строки (не как пароль пользователя, не как JWT). При `grant_type=refresh_token` сервер SHALL проверять хэш предъявленного `refresh_token`, срок действия, отсутствие отзыва **и `is_active` пользователя, к которому привязан токен**; при успехе SHALL отзывать предъявленный refresh-токен и выдавать новую пару (ротация). Предъявление уже отозванного refresh-токена SHALL приводить к отзыву всех refresh-токенов этого пользователя.

Размещение токена в cookie SHALL не ослаблять это правило ни в какой форме: сервер SHALL не заводить окна, внутри которого недавно отозванный токен принимается вместо гашения цепочки. Обоснование — в `design.md`, decision 7: предъявление недавно отозванного токена неотличимо на сервере от кражи, и послабление превратило бы обнаруживаемую кражу в тихое раздвоение цепочки. Одновременное обновление из нескольких вкладок одного браузера SHALL устраняться на стороне клиента (`admin-client-auth`), где стороны различимы.

#### Scenario: Неактивный пользователь не может получить новый access-токен через refresh, даже с действительным refresh-токеном
- **WHEN** пользователь заблокирован (`is_active = false` — `log-server-rbac`), но у него остался не отозванный, не истёкший refresh-токен, выданный до блокировки, и он предъявлен с `grant_type=refresh_token`
- **THEN** сервер отвечает ошибкой `invalid_grant` и не выдаёт новую пару токенов

#### Scenario: Успешное обновление ротирует токен
- **WHEN** отправлен `POST /v1/auth/token` с `grant_type=refresh_token` и валидным, не отозванным, не истёкшим `refresh_token`
- **THEN** сервер отвечает новой парой токенов, а предъявленный refresh-токен становится отозванным и больше не принимается ни в одном последующем запросе с `grant_type=refresh_token`

#### Scenario: Истёкший или отозванный refresh-токен отклоняется
- **WHEN** отправлен `POST /v1/auth/token` с `grant_type=refresh_token`, чей `expires_at` уже наступил, либо `revoked_at` уже установлен
- **THEN** сервер отвечает телом `{"error": "invalid_grant", ...}` и не выдаёт новую пару токенов

#### Scenario: Повторное использование отозванного refresh-токена отзывает все токены пользователя
- **WHEN** refresh-токен `A` пользователя был отозван (ротацией или через `DELETE /v1/auth/token`), и затем `A` повторно предъявлен с `grant_type=refresh_token`
- **THEN** сервер отвечает ошибкой `invalid_grant`, и все остальные ещё не отозванные refresh-токены этого пользователя также становятся отозванными

#### Scenario: Ротация не щадит токен оттого, что он предъявлен из cookie
- **WHEN** refresh-токен предъявлен из cookie, уже отозван ротацией мгновение назад, и предъявлен повторно
- **THEN** сервер отвечает `invalid_grant` и отзывает все токены учётной записи — так же, как для токена, предъявленного полем формы

### Requirement: Отзыв refresh-токена через DELETE /v1/auth/token (RFC 7009)
Сервер SHALL предоставлять `DELETE /v1/auth/token`, принимающий тело `application/x-www-form-urlencoded` с полем `refresh_token` (тот же путь, что создаёт токен через `POST`, но с методом, выражающим удаление ресурса), немедленно помечающий предъявленный refresh-токен отозванным; уже выданный вместе с ним access-токен SHALL оставаться технически валидным до истечения своего короткого срока действия. Вслед за RFC 7009 §2.2 сервер SHALL отвечать успехом (200, пустое тело) независимо от того, был ли предъявленный токен валиден, уже отозван или не существовал.

Токен SHALL браться из поля формы, если оно присутствует, и только при его отсутствии — из cookie; приоритет поля над cookie здесь особенно существен, поскольку от выбора зависит, *чья* сессия заканчивается. Единственная причина ответить ошибкой (400, формат RFC 6749 §5.2) — отсутствие и поля `refresh_token`, и cookie. Ответ на `DELETE` SHALL, когда запрос принёс cookie, гасить её (`Set-Cookie` с истёкшим сроком и теми же `Path`/атрибутами) — иначе браузер продолжил бы слать мёртвый токен до конца его номинального срока.

#### Scenario: Отозванный токен больше не работает
- **WHEN** выполнен `DELETE /v1/auth/token` с действующим `refresh_token` в form-encoded теле, а затем этот же токен предъявлен с `grant_type=refresh_token` на `POST /v1/auth/token`
- **THEN** сервер отвечает ошибкой `invalid_grant` на повторное использование

#### Scenario: Отзыв всегда отвечает успехом, не раскрывая валидность токена
- **WHEN** выполнен `DELETE /v1/auth/token` с `refresh_token`, который уже отозван, истёк или никогда не существовал
- **THEN** сервер отвечает 200 с пустым телом — так же, как при отзыве действительного токена, без различимой по ответу разницы

#### Scenario: Отсутствие и поля, и cookie отклоняется
- **WHEN** выполнен `DELETE /v1/auth/token` без поля `refresh_token` в form-encoded теле и без cookie
- **THEN** сервер отвечает 400 с телом `{"error": "invalid_request", ...}`

#### Scenario: Выход из браузера гасит cookie
- **WHEN** выполнен `DELETE /v1/auth/token` без поля формы, но с cookie, несущей действующий refresh-токен
- **THEN** токен отзывается, а ответ несёт `Set-Cookie`, стирающий cookie на том же `Path`, так что следующий запрос браузера её не принесёт
