## ADDED Requirements

### Requirement: Запрос даёт одну запись об итоге
Middleware `structured_log_shelf`, поставленный в `Pipeline`, SHALL писать на каждый запрос одну итоговую запись:
`http_request_handled`, если внутренний обработчик вернул `Response`, или `http_request_failed`, если он бросил
исключение. Итоговая запись SHALL содержать `method`, `path` (путь из `request.requestedUri`), `request_id`,
`duration_ms` (дробное число миллисекунд до возврата ответа или исключения) и `category` (по умолчанию `http`), а при
наличии ответа — `status_code`. Запись `http_request_received` с `method`, `path` и `request_id` SHALL писаться до вызова
обработчика только при ненулевом `ShelfLogLevels.received` (по умолчанию `null`).

#### Scenario: Успешный запрос
- **WHEN** обработчик на `GET /items` вернул ответ 200
- **THEN** записана одна запись `http_request_handled` с `method: GET`, `path: /items`, `status_code: 200`, `duration_ms` и `request_id`, и нет записи `http_request_received`

#### Scenario: Путь под точкой монтирования
- **WHEN** middleware стоит внутри обработчика, смонтированного под `/api/` (для него `request.url` — `items`), и выполнен запрос `GET /api/items`
- **THEN** `path` записи равен `/api/items`

#### Scenario: Запись о получении включена
- **WHEN** `ShelfLogLevels(received: LogLevel.debug)` и выполнен запрос
- **THEN** до итоговой записи записана `http_request_received` с тем же `request_id`

### Requirement: Уровень итога определяется исходом
Итог с ответом SHALL записываться на уровне `ShelfLogLevels.success` для статуса ниже 400 (по умолчанию `info`),
`clientError` для 4xx (`warning`) и `serverError` для 5xx (`error`). Итог с исключением SHALL записываться на уровне
`failure` (`error`). Значение `null` SHALL выключать соответствующую запись.

#### Scenario: Ошибка клиента
- **WHEN** обработчик вернул 404
- **THEN** `http_request_handled` записан на уровне `warning` со `status_code: 404`

#### Scenario: Выключенный уровень
- **WHEN** `ShelfLogLevels(success: null)` и обработчик вернул 200
- **THEN** итоговой записи нет, а ответ получен клиентом без изменений, кроме заголовка `request_id`

### Requirement: Исключение обработчика пишется и пробрасывается без изменений
Если внутренний обработчик бросил исключение, кроме `HijackException`, middleware SHALL записать `http_request_failed` с
типом, текстом и стеком исключения и SHALL пробросить то же исключение с исходным стеком. `HijackException` SHALL NOT
считаться сбоем: middleware SHALL записать `http_request_handled` с `hijacked: true` без `status_code` на уровне
`success` и SHALL пробросить `HijackException` без изменений.

#### Scenario: Бросивший обработчик
- **WHEN** обработчик бросает `StateError`
- **THEN** записан `http_request_failed` уровня `error` с `error_type`, `error` и `stack_trace`, а вызов middleware завершается тем же `StateError`

#### Scenario: Захват сокета
- **WHEN** обработчик, запущенный через `shelf_io.serve`, захватывает запрос через `request.hijack`
- **THEN** записан `http_request_handled` с `hijacked: true` без `status_code`, и соединение остаётся у обработчика

### Requirement: Обработчик получает логгер, привязанный к запросу
Middleware SHALL передавать внутреннему обработчику запрос, в `context` которого лежат `request_id` и `BoundLogger` с
этим `request_id` в поле `request_id` (словарь `LogCorrelation`). Расширение на `Request` SHALL отдавать их как
`request.logger` и `request.requestId`. Записи, сделанные через `request.logger`, SHALL содержать тот же `request_id`,
что итоговая запись middleware. Обращение к `request.logger` или `request.requestId` у запроса, не прошедшего через
middleware, SHALL бросать `StateError` с сообщением, называющим middleware.

#### Scenario: Запись обработчика коррелирует с запросом
- **WHEN** обработчик пишет `request.logger.warning('quota_exceeded')`, а затем возвращает 429
- **THEN** у записи `quota_exceeded` и у `http_request_handled` одинаковый `request_id`

#### Scenario: Разные запросы — разные id
- **WHEN** выполнены два запроса подряд
- **THEN** их `request_id` различаются

#### Scenario: Middleware не подключён
- **WHEN** обработчик вызван напрямую, без middleware, и читает `request.logger`
- **THEN** брошен `StateError`

### Requirement: Идентификатор запроса возвращается клиенту
Middleware SHALL добавлять `request_id` в заголовок ответа `responseHeader` (по умолчанию `X-Request-Id`); `null`
SHALL выключать заголовок. Функция `requestIdGenerator` SHALL заменять генерацию id по умолчанию.

#### Scenario: Заголовок ответа
- **WHEN** выполнен запрос с настройками по умолчанию
- **THEN** ответ несёт `X-Request-Id`, равный `request_id` итоговой записи

#### Scenario: Свой генератор
- **WHEN** `requestIdGenerator` возвращает `'fixed-1'`
- **THEN** `request_id` записи и заголовок ответа равны `fixed-1`

### Requirement: Входящий идентификатор принимается только явно и после проверки
По умолчанию middleware SHALL NOT читать входящий заголовок идентификатора и SHALL генерировать `request_id` сам. При
`trustIncomingRequestId: true` значение входящего заголовка (`incomingRequestIdHeader`, по умолчанию `X-Request-Id`)
SHALL использоваться как `request_id`, только если оно состоит из 1–128 символов набора `[A-Za-z0-9._:-]`; иначе
middleware SHALL сгенерировать id, записать в итоговую запись `request_id_rejected: true` и SHALL NOT писать
отвергнутое значение ни в одну запись.

#### Scenario: Недоверенный входящий id
- **WHEN** настройки по умолчанию и запрос несёт `X-Request-Id: abc`
- **THEN** `request_id` записи — сгенерированный, а не `abc`

#### Scenario: Доверенный корректный id
- **WHEN** `trustIncomingRequestId: true` и запрос несёт `X-Request-Id: 3f2a-proxy.17`
- **THEN** `request_id` записи и заголовок ответа равны `3f2a-proxy.17`

#### Scenario: Доверенный, но некорректный id
- **WHEN** `trustIncomingRequestId: true` и запрос несёт `X-Request-Id` со значением `"><script>` длиной меньше 128 символов
- **THEN** `request_id` записи — сгенерированный, запись содержит `request_id_rejected: true`, а строка `<script>` не встречается ни в одной записи

### Requirement: Секреты не попадают в лог
Тела запросов и ответов SHALL NOT писаться ни при каких настройках. Заголовки SHALL NOT писаться, пока не включён
`logHeaders`; при включённом — `request_headers` и `response_headers` SHALL писаться с заменой значений из
`redactedHeaders` (по умолчанию `authorization`, `proxy-authorization`, `cookie`, `set-cookie`, `x-api-key`) на
`REDACTED`. Непустой query SHALL писаться полем `query` с заменой значений параметров из `redactedQueryParameters`
(по умолчанию тот же набор, что у `structured_log_dio`) на `REDACTED`. Сравнение имён SHALL быть регистронезависимым.

#### Scenario: Тело с паролем
- **WHEN** обработчик читает `POST /token` с телом `password=s3cret-pw&username=body-user` и отвечает телом `token=s3cret-tok`
- **THEN** ни `s3cret-pw`, ни `body-user`, ни `s3cret-tok` не встречаются ни в одной записи middleware

#### Scenario: Заголовки по умолчанию
- **WHEN** запрос несёт `Authorization: Bearer t0ken`, `logHeaders` не задан
- **THEN** записи не содержат ни `request_headers`, ни `t0ken`

#### Scenario: Включённые заголовки
- **WHEN** `logHeaders: true`, запрос несёт `Authorization: Bearer t0ken` и `Accept: text/plain`, ответ — `Set-Cookie: sid=s3cret`
- **THEN** `request_headers` содержит `authorization: REDACTED` и `accept: text/plain`, `response_headers` — `set-cookie: REDACTED`, и ни `t0ken`, ни `s3cret` не встречаются ни в одной записи

#### Scenario: Токен в query
- **WHEN** запрос `GET /callback?access_token=t0ken&page=2`
- **THEN** `query` записи содержит `access_token=REDACTED` и `page=2`, и `t0ken` не встречается ни в одной записи

### Requirement: Фильтр убирает записи, но не корреляцию
Запрос, для которого `filter` вернул `false`, SHALL NOT давать записей middleware; такой запрос SHALL всё равно получать
`request_id`, логгер в `context` и заголовок ответа. Бросивший `filter` SHALL приводить к отсутствию записей
middleware для этого запроса (fail-closed) и SHALL NOT влиять на ответ.

#### Scenario: Health check вне журнала
- **WHEN** `filter` отвергает `/health`, выполнены `GET /health` и `GET /items`
- **THEN** записи middleware есть только для `/items`, а ответ на `/health` несёт `X-Request-Id`

#### Scenario: Бросивший фильтр
- **WHEN** `filter` бросает исключение
- **THEN** клиент получает ответ обработчика без изменений, кроме заголовка `request_id`, и записей middleware нет

### Requirement: Логирование не меняет исход запроса
Сбой при построении записи, маскировании, вызове лога или добавлении заголовка ответа SHALL NOT менять статус, тело
или исключение запроса; ответ, к которому заголовок не удалось добавить, SHALL уходить клиенту как есть.

#### Scenario: Бросающий sink
- **WHEN** единственный sink конфигурации бросает исключение на каждой записи, а обработчик возвращает 200 с телом `ok`
- **THEN** клиент получает 200 с телом `ok`

### Requirement: Логгер следует текущей конфигурации
Без явного `logger` middleware SHALL брать логгер через `getLogger(loggerName)` на каждом запросе, так что
`StructlogConfiguration.configure`, вызванный после сборки `Pipeline`, SHALL применяться к последующим записям
middleware и `request.logger`. Явно переданный `logger` SHALL использоваться как есть.

#### Scenario: Конфигурация после сборки Pipeline
- **WHEN** `Pipeline` собран, затем вызван `StructlogConfiguration.configure` с новым sink'ом, затем выполнен запрос
- **THEN** итоговая запись и запись обработчика доставлены в новый sink
