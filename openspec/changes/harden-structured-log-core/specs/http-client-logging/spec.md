## ADDED Requirements

### Requirement: Строковые тела маскируются по именам полей
При включённых телах тело с `Content-Type` JSON (`application/json`, `*+json`) или `application/x-www-form-urlencoded` SHALL разбираться, значения полей из `redactedBodyFields` (по умолчанию `defaultSensitiveKeys` из `structured_log`, сравнение регистронезависимое, на любой глубине) SHALL заменяться на `REDACTED`, и в запись SHALL попадать собранное обратно тело; `describeBody` SHALL получать уже замаскированное тело. Не разобравшееся тело этих типов SHALL записываться как `'<unparseable body>'`. Тело другого или неизвестного типа SHALL записываться только при `logUnrecognizedBodies: true` (по умолчанию `false`), иначе — как `'<N chars>'`. Тело ответа SHALL по-прежнему доходить до читателя без изменений.

#### Scenario: JSON-тело запроса
- **WHEN** `logRequestBody: true`, запрос с `Content-Type: application/json` и телом `{"refresh_token":"r","scope":"a"}`
- **THEN** `request_body` содержит `"scope":"a"` и `"refresh_token":"REDACTED"`, и `"r"` не встречается ни в одной записи

#### Scenario: Читатель получает исходное тело
- **WHEN** `logResponseBody: true`, ответ JSON с `access_token`
- **THEN** читатель получает исходное тело с токеном, а `response_body` — с `REDACTED`
