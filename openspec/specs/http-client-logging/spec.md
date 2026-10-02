# http-client-logging Specification

## Purpose
`StructuredLogHttpClient` (`emb/structured_log_http_client`) — обёртка `http.Client` из `package:http`, превращающая каждый HTTP-вызов в пару записей `structured_log` (отправка и итог) с уровнем по статусу ответа, маскированием секретов и логированием тела ответа без буферизации. Введена change `add-structured-log-http-client` (архив `openspec/changes/archive/2026-10-01-add-structured-log-http-client/`).
## Requirements
### Requirement: Вызов даёт запись на отправку и запись на итог
`StructuredLogHttpClient`, обёрнутый вокруг `http.Client`, SHALL писать запись `http_request` перед отправкой запроса во внутренний клиент и одну итоговую запись — `http_response`, если пришёл ответ с любым статусом, иначе `http_error`. Обе записи SHALL содержать `method`, `url`, одинаковый `http_request_id` и `category` (по умолчанию `http`); итоговая SHALL содержать `duration_ms`, а при наличии ответа — `status_code`. Исключение внутреннего клиента SHALL доходить до вызывающего кода без изменений.

#### Scenario: Успешный вызов
- **WHEN** выполнен GET-запрос, внутренний клиент вернул 200
- **THEN** записаны `http_request` и `http_response` с одинаковым `http_request_id`, у второй — `status_code: 200` и `duration_ms`

#### Scenario: Исключение внутреннего клиента
- **WHEN** внутренний клиент бросил `ClientException`
- **THEN** записан `http_error` уровня `error` с `error_type: ClientException` и `error`, без `status_code`, и вызывающий код получил то же исключение

### Requirement: Уровень итога определяется статусом ответа
`http_response` SHALL записываться на уровне `HttpLogLevels.success` для статуса ниже 400, `clientError` для 4xx и `serverError` для 5xx. `http_error` SHALL записываться на уровне `cancel`, если причина — `RequestAbortedException`, иначе на уровне `failure`. Значение `null` SHALL выключать соответствующую запись.

#### Scenario: Статусы 301, 404, 503
- **WHEN** внутренний клиент ответил 301, 404 и 503 на три запроса
- **THEN** записаны три `http_response` с уровнями `debug`, `warning` и `error`

#### Scenario: Прерванный запрос
- **WHEN** запрос `AbortableRequest` прерван через `abortTrigger`
- **THEN** записан `http_error` с `error_type: RequestAbortedException` на уровне `debug`

### Requirement: Секреты не попадают в лог без явного включения
Заголовки и тела SHALL NOT писаться, пока не включены `logHeaders`/`logRequestBody`/`logResponseBody`. При включённых заголовках значения заголовков из `redactedHeaders` SHALL заменяться на `REDACTED`. Значения query-параметров из `redactedQueryParameters` SHALL заменяться на `REDACTED` и user info SHALL удаляться из `url` всегда. Сравнение имён SHALL быть регистронезависимым.

#### Scenario: Заголовок авторизации при включённых заголовках
- **WHEN** `logHeaders: true` и запрос несёт `Authorization: Bearer <token>`
- **THEN** `request_headers` содержит `Authorization: REDACTED`, и значение токена не встречается ни в одной записи

#### Scenario: Токен в query
- **WHEN** URL запроса содержит `access_token=<token>` и `user:pass@`
- **THEN** `url` записи содержит `access_token=REDACTED` и не содержит ни токена, ни user info

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

### Requirement: Клиент не меняет исход вызова
Исключение из `filter`, `describeBody` или логирования SHALL NOT выходить из клиента; бросившая `describeBody` SHALL стоить записи её тела, а не самой записи.

#### Scenario: Бросающая функция описания
- **WHEN** `describeBody` бросает исключение при включённом `logResponseBody`
- **THEN** вызов завершается ответом 200, а `http_response` записан с `describe_failed`

### Requirement: Фильтр исключает обе записи вызова
Запрос, для которого `filter` вернул `false`, SHALL NOT давать ни записи на отправку, ни итоговой записи.

#### Scenario: Health-check вне лога
- **WHEN** `filter` отвергает путь `/health`, выполнены запросы на `/health` и `/items`
- **THEN** записи есть только для `/items`

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

