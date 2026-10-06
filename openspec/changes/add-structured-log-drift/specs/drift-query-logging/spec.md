## ADDED Requirements

### Requirement: Каждый запрос даёт запись db_query
`StructuredLogDriftInterceptor`, подключённый через `interceptWith`, SHALL писать одну запись `db_query` на каждый выполненный запрос. Запись SHALL содержать:
- `kind` — одно из `select`, `insert`, `update`, `delete`, `custom`;
- `statement` — текст SQL, обрезанный до 2000 символов;
- `duration_ms` — дробное число миллисекунд;
- `category: 'db'`.

У `select` запись SHALL содержать `rows` (число строк результата), у `update` и `delete` — `affected_rows`, у `insert` — `insert_id`.

#### Scenario: Выборка
- **WHEN** выполнен `customSelect('SELECT * FROM t')`, и в таблице три строки
- **THEN** записана одна запись `db_query` с `kind: 'select'`, `statement: 'SELECT * FROM t'`, `rows: 3`, числовым `duration_ms` и `category: 'db'`

#### Scenario: Обновление
- **WHEN** выполнен `customUpdate`, затронувший две строки
- **THEN** запись `db_query` содержит `kind: 'update'` и `affected_rows: 2`

#### Scenario: Вставка
- **WHEN** выполнен `customInsert`, вставивший строку с id 7
- **THEN** запись `db_query` содержит `kind: 'insert'` и `insert_id: 7`

### Requirement: Аргументы по умолчанию не пишутся
По умолчанию запись SHALL NOT содержать значений аргументов запроса, в том числе в тексте ошибки: хвост `parameters:` сообщения `sqlite3` SHALL заменяться на `<hidden>`, а строковые аргументы длиной от 4 символов — на `<argument>`. При `logArguments: true` запись `db_query` SHALL содержать поле `arguments`: строки обрезаются до 1000 символов, `Uint8List` пишется как `<N bytes>`. Запись `db_batch` SHALL NOT содержать аргументов никогда.

#### Scenario: Аргументы скрыты
- **WHEN** выполнен `customSelect('SELECT * FROM users WHERE token = ?', variables: [Variable('secret-token')])`
- **THEN** ни одна запись не содержит `secret-token`

#### Scenario: Аргументы в тексте ошибки
- **WHEN** `logArguments` выключен, и запрос с аргументом `'secret-token'` падает с исключением, текст которого перечисляет параметры
- **THEN** запись `db_query_failed` содержит `error` и `error_type`, но не содержит `secret-token`

#### Scenario: Аргументы включены
- **WHEN** перехватчик создан с `logArguments: true`, и выполнен запрос с аргументами `'a'` и `Uint8List(16)`
- **THEN** запись содержит `arguments: ['a', '<16 bytes>']`

### Requirement: Медленный запрос выделяется уровнем
Запрос или пакет, длительность которого не меньше `slowQueryThreshold` (по умолчанию 500 мс), SHALL писаться уровнем `slow` (по умолчанию `warning`) и с полем `slow: true`. Остальные запросы SHALL писаться уровнем `query` (по умолчанию `debug`). `slowQueryThreshold: null` SHALL выключать отметку.

#### Scenario: Медленный запрос
- **WHEN** порог задан как `Duration.zero`, и выполнен любой запрос
- **THEN** запись `db_query` имеет уровень `warning` и `slow: true`

#### Scenario: Быстрый запрос
- **WHEN** порог по умолчанию, и выполнен `SELECT 1`
- **THEN** запись `db_query` имеет уровень `debug` и не содержит `slow`

### Requirement: Пакет даёт одну запись db_batch
Вызов `batch` SHALL давать одну запись `db_batch` с `statement_count` (число различных операторов), `execution_count` (число выполнений) и `duration_ms`, а SHALL NOT давать записей `db_query` на отдельные операторы.

#### Scenario: Пакет одинаковых вставок
- **WHEN** в `batch` дважды выполнен один и тот же `INSERT` с разными аргументами
- **THEN** записана одна запись `db_batch` с `statement_count: 1` и `execution_count: 2`

### Requirement: Упавший запрос пишется и пробрасывается без изменений
Если запрос или пакет бросил, перехватчик SHALL писать запись `db_query_failed` уровня `failed` (по умолчанию `error`) с `kind`, `statement`, `duration_ms`, `error`, `error_type` и `stack_trace`. Исключение SHALL доходить до вызывающего тем же объектом.

#### Scenario: Запрос к несуществующей таблице
- **WHEN** выполнен `customStatement('INSERT INTO nope VALUES (1)')`
- **THEN** вызывающий получает то же `SqliteException`, а записана `db_query_failed` с `kind: 'custom'`, `error_type: 'SqliteException'` и `stack_trace`

### Requirement: Завершение транзакции пишется
Коммит транзакции SHALL давать запись `db_transaction_committed` (по умолчанию уровня `trace`), откат — `db_transaction_rolled_back` (по умолчанию уровня `warning`). Обе записи SHALL содержать `duration_ms` от начала своей транзакции, в том числе для вложенной.

#### Scenario: Откат
- **WHEN** внутри `transaction()` запрос бросает
- **THEN** записаны `db_query_failed`, затем `db_transaction_rolled_back` с `duration_ms`

#### Scenario: Вложенная транзакция
- **WHEN** транзакция содержит вложенную транзакцию, и обе завершаются успешно
- **THEN** записаны две записи `db_transaction_committed`, у внутренней `duration_ms` не больше, чем у внешней

### Requirement: Уровни настраиваются на вид записи
`DriftLogLevels` SHALL задавать уровни `query`, `batch`, `slow`, `failed`, `committed`, `rolledBack`. `null` SHALL выключать соответствующую запись.

#### Scenario: Запросы выключены
- **WHEN** перехватчик создан с `DriftLogLevels(query: null)`, выполнены быстрый запрос и упавший запрос
- **THEN** записи `db_query` нет, а `db_query_failed` записана

### Requirement: Фильтр отсекает запросы
Функция `filter(kind, statement)`, вернувшая `false`, SHALL исключать записи этого запроса. Бросивший `filter` SHALL исключать запись, а запрос SHALL выполняться как обычно.

#### Scenario: Служебные запросы отсечены
- **WHEN** `filter` возвращает `false` для текста, начинающегося с `PRAGMA`
- **THEN** записей о `PRAGMA` нет, а остальные запросы записаны

#### Scenario: Бросающий фильтр
- **WHEN** `filter` бросает `StateError`, и выполнен `SELECT 1`
- **THEN** запрос возвращает результат, записи о нём нет, и обработчик ошибок зоны не вызван

### Requirement: Логирование не меняет запрос
Сбой логирования (фильтр, логгер, sink) SHALL NOT менять результат запроса и SHALL NOT давать исключения вызывающему.

#### Scenario: Падающий sink
- **WHEN** единственный sink `structured_log` бросает на каждой записи, и выполнен `SELECT 1`
- **THEN** запрос возвращает одну строку и не бросает

### Requirement: Повторная конфигурация доходит до перехватчика
Если `BoundLogger` не передан явно, перехватчик SHALL использовать конфигурацию `structured_log`, действующую в момент запроса.

#### Scenario: configure после подключения
- **WHEN** перехватчик подключён, затем вызван `StructlogConfiguration.configure` с новым выводом, затем выполнен запрос
- **THEN** запись `db_query` получает новый вывод
