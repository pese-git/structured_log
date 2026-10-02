# dio-log-interceptor Specification

## Purpose
`StructuredLogDioInterceptor` (`emb/structured_log_dio`) — перехватчик `dio`, превращающий каждый HTTP-вызов в пару записей `structured_log` (отправка и итог) с уровнем по статусу ответа и маскированием секретов. Введена change `add-structured-log-dio` (архив `openspec/changes/archive/2026-10-01-add-structured-log-dio/`).
## Requirements
### Requirement: Вызов даёт запись на отправку и запись на итог
`StructuredLogDioInterceptor`, добавленный в `Dio.interceptors`, SHALL писать запись `http_request` перед отправкой запроса и одну итоговую запись — `http_response`, если ответ принят `validateStatus`, иначе `http_error`. Обе записи SHALL содержать `method`, `url`, одинаковый `http_request_id` и `category` (по умолчанию `http`); итоговая SHALL содержать `duration_ms`, а при наличии ответа — `status_code`.

#### Scenario: Успешный вызов
- **WHEN** выполнен GET-запрос, сервер ответил 200
- **THEN** записаны `http_request` и `http_response` с одинаковым `http_request_id`, у второй — `status_code: 200` и `duration_ms`

#### Scenario: Сбой без ответа
- **WHEN** адаптер не смог установить соединение
- **THEN** записан `http_error` уровня `error` с `error_type: connectionError`, `error` и `duration_ms`, без `status_code`

### Requirement: Уровень итога определяется статусом ответа
Итог с ответом SHALL записываться на уровне `HttpLogLevels.success` для статуса ниже 400, `clientError` для 4xx и `serverError` для 5xx — независимо от того, пришёл ли ответ через `onResponse` или через `onError`. Итог без ответа SHALL записываться на уровне `failure`, отмена — на уровне `cancel`. Значение `null` SHALL выключать соответствующую запись.

#### Scenario: 404 при любом validateStatus
- **WHEN** сервер ответил 404 один раз при `validateStatus` по умолчанию и один раз при `validateStatus`, принимающем любой статус
- **THEN** оба итога (`http_error` и `http_response`) записаны на уровне `warning` со `status_code: 404`

### Requirement: Секреты не попадают в лог без явного включения
Заголовки и тела SHALL NOT писаться, пока не включены `logHeaders`/`logRequestBody`/`logResponseBody`. При включённых заголовках значения заголовков из `redactedHeaders` SHALL заменяться на `REDACTED`. Значения query-параметров из `redactedQueryParameters` SHALL заменяться на `REDACTED` и user info SHALL удаляться из `url` всегда. Сравнение имён SHALL быть регистронезависимым.

#### Scenario: Заголовок авторизации при включённых заголовках
- **WHEN** `logHeaders: true` и запрос несёт `Authorization: Bearer <token>`
- **THEN** `request_headers` содержит `Authorization: REDACTED`, и значение токена не встречается ни в одной записи

#### Scenario: Токен в query
- **WHEN** URL запроса содержит `access_token=<token>` и `user:pass@`
- **THEN** `url` записи содержит `access_token=REDACTED` и не содержит ни токена, ни user info

### Requirement: Тела описываются заменяемой функцией
Включённые тела SHALL сначала маскироваться (см. «Тела маскируются по именам полей до сериализации»), затем попадать в запись через `describeBody` (по умолчанию строка: словари и списки в JSON, байты/потоки/`FormData` кратко, обрезка до 1000 символов); `describeBody` SHALL получать уже замаскированное тело; возврат `null` SHALL убирать поле.

#### Scenario: Тело ответа с ошибкой
- **WHEN** `logResponseBody: true`, сервер ответил 422 с телом
- **THEN** `http_error` содержит `response_body` с этим телом

#### Scenario: Своя функция видит замаскированное
- **WHEN** `logRequestBody: true`, тело `{'password': 'p'}` и `describeBody` возвращает тело как есть
- **THEN** `request_body` не содержит `'p'`

### Requirement: Перехватчик не меняет исход вызова
Исключение из `filter`, `describeBody` или логирования SHALL NOT выходить из перехватчика, и каждый хук SHALL передавать управление дальше по цепочке.

#### Scenario: Бросающая функция описания
- **WHEN** `describeBody` бросает исключение при включённом `logResponseBody`
- **THEN** вызов завершается ответом 200, а итоговая запись содержит `describe_failed`

### Requirement: Фильтр исключает обе записи вызова
Запрос, для которого `filter` вернул `false`, SHALL NOT давать ни записи на отправку, ни итоговой записи.

#### Scenario: Health-check вне лога
- **WHEN** `filter` отвергает путь `/health`, выполнены запросы на `/health` и `/items`
- **THEN** записи есть только для `/items`

### Requirement: Тела маскируются по именам полей до сериализации
При включённых телах значения полей из `redactedBodyFields` (по умолчанию `defaultSensitiveKeys` из `structured_log`, сравнение регистронезависимое, на любой глубине) SHALL заменяться на `REDACTED` до сериализации: в `Map`/`List` — напрямую; в строковом теле с `Content-Type` JSON (`application/json`, `*+json`) или `application/x-www-form-urlencoded` — после разбора. Строковое тело указанных типов, которое не разобралось, SHALL записываться как `'<unparseable body>'`. Строковое тело другого или неизвестного типа SHALL записываться только при `logUnrecognizedBodies: true` (по умолчанию `false`), иначе — как `'<N chars>'`.

#### Scenario: Тело запроса токена
- **WHEN** `logRequestBody: true`, POST с телом `{'username': 'u', 'password': 'p', 'client_secret': 's'}`
- **THEN** `request_body` содержит `username`, а `password` и `client_secret` — `REDACTED`; ни `'p'`, ни `'s'` не встречаются ни в одной записи

#### Scenario: Form-urlencoded строкой
- **WHEN** `logRequestBody: true`, тело `'grant_type=password&password=p'` с `Content-Type: application/x-www-form-urlencoded`
- **THEN** `request_body` содержит `password=REDACTED` и `grant_type=password`

#### Scenario: Строка неизвестного типа
- **WHEN** `logRequestBody: true`, тело `'secret=p'` без `Content-Type`
- **THEN** `request_body` равно `'<8 chars>'`

