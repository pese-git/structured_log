# structured-log-core Specification

## Purpose
Надёжность ядра `structured_log` (`emb/structured_log`): вызов лога не бросает никогда (бросивший процессор даёт заглушку, а не исходную запись), несериализуемое значение стоит одного поля (`encodeLogEntry`), метка времени однозначна (UTC по умолчанию), уровень проверяется до обработки, логгер из `getLogger()` следует текущей конфигурации, форматтеры — выходы, а не процессоры, logfmt экранируется, главная библиотека не зависит от `dart:io` (файловые выходы — в `io.dart`). Введена change `harden-structured-log-core` (архив `openspec/changes/archive/2026-10-02-harden-structured-log-core/`), выпущена как `structured_log 0.3.0`.
## Requirements
### Requirement: Вызов лога никогда не бросает
Методы `BoundLogger` (`tryLog`, `trace`, `debug`, `info`, `warning`, `error`, `critical`) SHALL NOT пропускать в место вызова ни одно исключение или `Error`, возникшее при склейке контекста, в процессоре, при кодировании записи, в выходе или во внутреннем репортёре — на любой платформе, включая web.

#### Scenario: Бросивший процессор
- **WHEN** в `processors` стоит процессор, бросающий `StateError`, и вызывается `log.info('x')`
- **THEN** вызов возвращается без исключения

#### Scenario: Сломанный выход на web
- **WHEN** на web выход sink'а бросает исключение
- **THEN** вызов лога возвращается без исключения, и сообщение о сбое выведено внутренним репортёром через `print`

### Requirement: Сбой процессора даёт заглушку, а не исходную запись
Если процессор бросает, запись SHALL заменяться заглушкой, содержащей только `event`, `level`, `timestamp`, `logger` и `category` (те из них, что были в записи) и `processor_failed` с именем типа исключения; процессоры после бросившего SHALL NOT выполняться; заглушка SHALL доставляться sink'ам по обычным правилам фильтрации. Текст исключения SHALL NOT попадать в заглушку.

#### Scenario: Маскирующий процессор упал
- **WHEN** запись с `password: 'p'` проходит через процессор, бросающий до маскирования
- **THEN** sink получает запись с `processor_failed: 'StateError'`, без поля `password` и без значения `'p'`

### Requirement: Несериализуемое значение не стоит записи
Все встроенные выходы SHALL кодировать запись через `encodeLogEntry`, который SHALL кодировать `DateTime` как ISO-8601 в UTC, `Enum` как `name`, `Duration` как число микросекунд, `Set` как массив, объект с методом `toJson()` — как то, что этот метод вернёт (как `jsonEncode` без `toEncodable`), остальные значения, не принимаемые JSON, и объект с бросающим `toJson()` — через `toString()`, а значение с бросающим `toString()` — как `'<ИмяТипа>'`. Если запись не кодируется и так (цикл), выход SHALL получить заглушку с `encoding_failed`.

#### Scenario: Объекты в контексте ошибки
- **WHEN** `log.error('payment_failed', context: {'at': DateTime.utc(2026, 10, 2), 'cause': StateError('x'), 'level_hint': LogLevel.info})` пишется в `fileOutput`
- **THEN** в файле одна строка JSON с `"at":"2026-10-02T00:00:00.000Z"`, `"cause":"Bad state: x"`, `"level_hint":"info"`

#### Scenario: DTO с toJson в контексте
- **WHEN** в контексте объект, чей `toJson()` возвращает `{'name': 'alice', 'joined': DateTime.utc(2026, 10, 5)}`
- **THEN** выход получает поле объектом JSON `{"name":"alice","joined":"2026-10-05T00:00:00.000Z"}`, а не строкой `toString()`

#### Scenario: Цикл без маскирования
- **WHEN** в контексте карта, содержащая саму себя, и процессоров маскирования нет
- **THEN** выход получает запись с `encoding_failed`, и вызов не бросает

### Requirement: redactKeys видит то, что будет записано
`redactKeys` SHALL обходить, кроме карт и списков, множества (`Set`) и то, что возвращает `toJson()` объекта, так как выход запишет объект именно этим. Если внутри найдено совпадение, на месте множества SHALL оказаться список, а на месте объекта — замаскированная карта или список. Если совпадений нет, а также если `toJson()` нет или он бросил, SHALL оставаться исходный объект.

#### Scenario: DTO с паролем
- **WHEN** контекст содержит объект, чей `toJson()` возвращает `{'name': 'alice', 'password': 'hunter2'}`
- **THEN** после `redactKeys()` поле равно `{'name': 'alice', 'password': '***'}`, и `hunter2` не встречается в закодированной записи

#### Scenario: Множество карт
- **WHEN** контекст содержит `{'users': {{'password': 'x'}}}`
- **THEN** после `redactKeys()` поле `users` равно `[{'password': '***'}]`

### Requirement: redactKeys переносит циклы
`redactKeys` SHALL заменять повторный вход в уже посещённый контейнер на `'<cycle>'` и SHALL NOT бросать на циклической записи; запись без совпадений и без циклов SHALL возвращаться тем же объектом.

#### Scenario: Цикл с секретом
- **WHEN** контекст содержит карту `m` с `token: 't'` и `self: m`
- **THEN** результат содержит `token: '***'` и `self: '<cycle>'`, исходная `m` не изменена

### Requirement: Метка времени однозначна
`timestamp` SHALL по умолчанию записываться в UTC в формате ISO-8601 с суффиксом `Z`. При `timestampMode: TimestampMode.localWithOffset` SHALL записываться локальное время со смещением (`±HH:MM`). Формат без зоны SHALL NOT производиться ни в одном режиме.

#### Scenario: По умолчанию
- **WHEN** запись создана с конфигурацией по умолчанию
- **THEN** `timestamp` оканчивается на `Z`, и `DateTime.parse(timestamp).isUtc` истинно

#### Scenario: Локальное со смещением
- **WHEN** `timestampMode: TimestampMode.localWithOffset` в часовом поясе UTC+3
- **THEN** `timestamp` оканчивается на `+03:00`

### Requirement: Уровень проверяется до обработки
`BoundLogger.isEnabled(level, {String? category})` SHALL отвечать, примет ли запись хотя бы один включённый sink. `tryLog` SHALL завершаться до склейки контекста и процессоров, если ни один включённый sink не принимает `level`.

#### Scenario: trace без принимающего sink'а
- **WHEN** все sink'и с `minLevel: LogLevel.debug` и вызывается `log.trace('x')` с процессором-счётчиком
- **THEN** счётчик не увеличился, и `log.isEnabled(LogLevel.trace)` ложно

### Requirement: Ошибка и стек передаются параметрами
`tryLog` и все методы уровня SHALL принимать необязательные `Object? error` и `StackTrace? stackTrace` и SHALL записывать их полями `error` (`toString()`), `error_type` (имя типа) и `stack_trace` (`toString()`); явный параметр SHALL перекрывать одноимённый ключ `context`.

#### Scenario: Ошибка с параметрами
- **WHEN** `log.error('charge_failed', error: StateError('timeout'), stackTrace: st)`
- **THEN** запись содержит `error: 'Bad state: timeout'`, `error_type: 'StateError'` и `stack_trace` со строкой `st`

### Requirement: Логгер следует текущей конфигурации
Логгер, полученный через `getLogger()`, SHALL на каждой записи использовать `StructlogConfiguration.current` и его `initialContext` на момент записи. `BoundLogger`, созданный с явной конфигурацией, SHALL использовать её.

#### Scenario: Логгер создан до configure
- **WHEN** `final log = getLogger();` выполнен до `StructlogConfiguration.configure(output: capture)`, затем `log.info('x')`
- **THEN** запись получил `capture`

### Requirement: Форматтеры — выходы, а не процессоры
Пакет SHALL предоставлять `jsonLineOutput` и `logfmtOutput` как `OutputFunction`. `jsonRenderer`, `logfmtRenderer`, `addLogLevel` и `addTimestamp` SHALL быть помечены `@Deprecated`.

#### Scenario: JSON-строка из sink'а
- **WHEN** sink с `output: jsonLineOutput` получает запись
- **THEN** в stdout выведена ровно одна строка — JSON записи

### Requirement: logfmt не допускает подделки
`logfmtOutput` и `logfmtRenderer` SHALL выводить запись одной строкой: строковые значения в кавычках с экранированием `\`, `"`, `\n`, `\r`, `\t` и прочих управляющих символов; символы ключа вне `[A-Za-z0-9_.-]` SHALL заменяться на `_`.

#### Scenario: Ввод с переводом строки и кавычкой
- **WHEN** значение `user` равно `"a\" level=critical\nevent=\"forged"`
- **THEN** вывод — одна строка, в которой единственное поле `level` — настоящий уровень записи

### Requirement: Главная библиотека не зависит от dart:io
`package:structured_log/structured_log.dart` и всё, что из неё достижимо, SHALL NOT импортировать `dart:io` безусловно. Файловые выходы (`fileOutput`, `rotatingFileOutput`, `AsyncFileOutput`, `AsyncRotatingFileOutput`) SHALL экспортироваться из `package:structured_log/io.dart`.

#### Scenario: Сборка под web
- **WHEN** web-приложение импортирует только `package:structured_log/structured_log.dart`
- **THEN** ни один достижимый файл не импортирует `dart:io` (проверяется тестом-стражем)

### Requirement: Ротация не опрашивает файловую систему на каждую запись
Выходы с ротацией SHALL определять размер файла один раз при создании и далее вести его в памяти, SHALL NOT вызывать `exists`/`length` на каждую запись и SHALL ротировать, когда учтённый размер достиг `maxSizeBytes`.

#### Scenario: Ротация по учтённому размеру
- **WHEN** `rotatingFileOutput` с `maxSizeBytes: 100` получает записи суммарно больше 100 байт
- **THEN** появляется `<file>.0`, а текущий файл начинается заново

