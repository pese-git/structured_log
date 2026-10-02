## MODIFIED Requirements

### Requirement: Тело ответа логируется без буферизации
При `logResponseBody: true` клиент SHALL возвращать ответ, тело которого доходит до читателя по мере поступления и без изменений, и SHALL писать `http_response` с `response_body` после того, как тело дочитано или читатель отписался; ошибка в потоке тела SHALL давать `http_error` со `status_code`. Ответ SHALL сохранять `BaseResponseWithUrl.url`, если он был у исходного. Что именно попадает в `response_body`, определяет требование «Строковые тела маскируются по именам полей».

#### Scenario: Запись ждёт тело
- **WHEN** `logResponseBody: true`, ответ получен, но тело ещё не прочитано
- **THEN** записан только `http_request`; после чтения тела до конца записан `http_response` с `response_body`

#### Scenario: Читатель отписался раньше конца
- **WHEN** `logResponseBody: true` и `logUnrecognizedBodies: true`, читатель потока событий (`text/event-stream`) получил первый кусок и отписался
- **THEN** записан `http_response` с `response_body`, содержащим полученное

#### Scenario: Длинное тело
- **WHEN** `logResponseBody: true` и `logUnrecognizedBodies: true`, тело ответа `text/plain` длиной 10 000 символов
- **THEN** читатель получает все 10 000 символов, а `response_body` обрезан до 1000 символов с `…` в конце

## ADDED Requirements

### Requirement: Строковые тела маскируются по именам полей
При включённых телах тело с `Content-Type` JSON (`application/json`, `*+json`) или `application/x-www-form-urlencoded` SHALL читаться целиком до 64 КиБ, разбираться, значения полей из `redactedBodyFields` (по умолчанию `defaultSensitiveKeys` из `structured_log`, сравнение регистронезависимое, на любой глубине) SHALL заменяться на `REDACTED`, и в запись SHALL попадать собранное обратно тело; `describeBody` SHALL получать уже замаскированное тело. Тело этих типов, которое не разобралось или длиннее 64 КиБ, SHALL записываться как `'<unparseable body>'`. Текстовое тело другого или неизвестного типа SHALL записываться только при `logUnrecognizedBodies: true` (по умолчанию `false`), иначе — как `'<N bytes>'`: у клиента тело — байты, и у ответа известно только их число. Тело ответа SHALL по-прежнему доходить до читателя без изменений.

#### Scenario: JSON-тело запроса
- **WHEN** `logRequestBody: true`, запрос с `Content-Type: application/json` и телом `{"refresh_token":"r","scope":"a"}`
- **THEN** `request_body` содержит `"scope":"a"` и `"refresh_token":"REDACTED"`, и `"r"` не встречается ни в одной записи

#### Scenario: Читатель получает исходное тело
- **WHEN** `logResponseBody: true`, ответ JSON с `access_token`
- **THEN** читатель получает исходное тело с токеном, а `response_body` — с `REDACTED`

#### Scenario: Длиннее прежнего захвата
- **WHEN** `logResponseBody: true`, ответ JSON длиной около 6000 байт с `id_token`
- **THEN** `response_body` начинается с `{"id_token":"REDACTED"`, обрезан до 1000 символов, и значение токена не встречается ни в одной записи

#### Scenario: Текст неизвестного типа
- **WHEN** `logResponseBody: true`, ответ `text/plain` с телом `token: t-secret`
- **THEN** `response_body` равно `'<15 bytes>'`
