## MODIFIED Requirements

### Requirement: Тела описываются заменяемой функцией
Включённые тела SHALL сначала маскироваться (см. «Тела маскируются по именам полей до сериализации»), затем попадать в запись через `describeBody` (по умолчанию строка: словари и списки в JSON, байты/потоки/`FormData` кратко, обрезка до 1000 символов); `describeBody` SHALL получать уже замаскированное тело; возврат `null` SHALL убирать поле.

#### Scenario: Тело ответа с ошибкой
- **WHEN** `logResponseBody: true`, сервер ответил 422 с телом
- **THEN** `http_error` содержит `response_body` с этим телом

#### Scenario: Своя функция видит замаскированное
- **WHEN** `logRequestBody: true`, тело `{'password': 'p'}` и `describeBody` возвращает тело как есть
- **THEN** `request_body` не содержит `'p'`

## ADDED Requirements

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
