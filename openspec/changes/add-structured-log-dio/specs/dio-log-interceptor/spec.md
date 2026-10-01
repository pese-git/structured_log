## ADDED Requirements

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
Включённые тела SHALL попадать в запись через `describeBody` (по умолчанию строка: словари и списки в JSON, байты/потоки/`FormData` кратко, обрезка до 1000 символов); возврат `null` SHALL убирать поле.

#### Scenario: Тело ответа с ошибкой
- **WHEN** `logResponseBody: true`, сервер ответил 422 с телом
- **THEN** `http_error` содержит `response_body` с этим телом

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
