## Why

Внешний обзор `structured_log` 0.2.2+1 и интеграций (`_dio`/`_bloc` 0.1.0-dev.2, `_flutter` 0.1.1+2), сверенный с исходниками, нашёл четыре группы проблем, из-за которых пакет нельзя рекомендовать в продакшен (банковский клиент — прямо названный сценарий):

1. **Логирование ломает то, что логирует.** `BoundLogger.tryLog` защищает только вызов выхода; цепочка процессоров (`_processEntry`) идёт без `try`, так что бросивший процессор — или `redactKeys` на цикле (`StackOverflowError`) — уходит в место вызова, вопреки обещанию документации. Все выходы зовут `jsonEncode` без `toEncodable`: `DateTime`, `Exception`, enum в контексте — и запись теряется целиком, а у `RemoteSyncLogOutput` — **весь пакет** до `batchSize` записей (`jsonEncode(entries)` в `_HttpBatchSender.send`, ошибка ловится насосом, пакет выбрасывается). Время пишется `DateTime.now().toIso8601String()` — локальное **без смещения**, и сервер (`DateTime.tryParse` в `ingest.dart`) читает его как своё локальное: запись с устройства в UTC+3 ложится на три часа мимо. На web аварийная ветка `stderr.writeln` сама бросает `UnsupportedError` — сломанный выход всё-таки роняет вызов.
2. **Маскирование не доходит до тел.** `describeHttpBody` в `_dio` сериализует `Map` в строку до процессоров, и `redactKeys` видит строку, а не поле `password`; строковое тело (`x-www-form-urlencoded`, JSON-строка) уходит как есть. `_http_client` — то же для строковых тел. `logfmtRenderer` не экранирует кавычки и переводы строк — пользовательский ввод подделывает поля и строки лога.
3. **API ядра подталкивает к ошибкам.** Уровень проверяется в `LogSink.accepts` после склейки контекста и всех процессоров — `trace` в горячем цикле стоит полной цены. У `error()`/`critical()` нет параметров `error`/`stackTrace`. `getLogger()` фиксирует конфигурацию при создании: логгер в `static final`, созданный до `configure()`, молча пишет в stdout. `jsonRenderer`/`logfmtRenderer` печатают изнутри цепочки процессоров. `addLogLevel` ничего не делает, `addTimestamp` дублирует `tryLog`.
4. **Платформы.** Главная библиотека безусловно импортирует `dart:io` (ради `stderr` и файловых выходов) — pub.dev не отмечает пакет как web-совместимый, хотя web-клиент репозитория на нём работает. Выход по умолчанию — многострочный JSON через `print`, неудобный в logcat/Xcode. `LogBuffer` копирует весь список и уведомляет слушателей на каждую запись. Выходы с ротацией делают `exists`/`length` на каждую запись.

## What Changes

- **Изоляция и надёжность (ядро).** Исключение процессора больше не выходит из вызова лога: запись заменяется заглушкой с `processor_failed` (fail-closed — немаскированное содержимое не доставляется). `redactKeys` переносит циклы. Общий безопасный кодировщик записи (`encodeLogEntry`) со штатным `toEncodable` (`DateTime` → ISO-8601 UTC, enum → `name`, прочее → `toString()`, бросивший `toString()` → заглушка с типом) — его используют все встроенные выходы и `structured_log_remote_sync`. Внутренняя диагностика — через платформенный репортёр без `dart:io` в главной библиотеке.
- **BREAKING:** `timestamp` по умолчанию — UTC с `Z`; локальное время — явной опцией конфигурации.
- **`structured_log_remote_sync`:** запись кодируется **при постановке в очередь**, по одной; некодируемая запись (после безопасного кодировщика — только экзотика вроде бросающего `toEncodable`) отбрасывается поштучно, пакет собирается из готовых строк.
- **Маскирование тел.** `_dio`: `Map`/`List` маскируются по именам полей до сериализации, строковые тела с `Content-Type` JSON или `x-www-form-urlencoded` разбираются, маскируются и собираются обратно; набор полей — `redactedBodyFields`, по умолчанию `defaultSensitiveKeys` ядра. `_http_client` — то же для строковых тел. Остальные строковые тела (неизвестный тип) пишутся только по явному согласию.
- **logfmt.** Ключи и значения экранируются (кавычки, `\`, переводы строк, управляющие символы); значение с пробелом или `=` всегда в кавычках.
- **API ядра (обратно совместимо, кроме ленивой конфигурации).** `BoundLogger.isEnabled(level, {category})` и ранний выход в `tryLog`, если ни один включённый sink не примет уровень. Параметры `error`/`stackTrace` у `tryLog`/`error`/`critical` (и прочих уровней) → поля `error`, `error_type`, `stack_trace`. **BREAKING:** `getLogger()` без явной конфигурации читает `StructlogConfiguration.current` на каждой записи. Форматтеры для выходов — `jsonLineOutput`, `logfmtOutput`; `jsonRenderer`/`logfmtRenderer`/`addLogLevel`/`addTimestamp` помечены `@Deprecated`.
- **BREAKING: платформы.** Файловые выходы (`fileOutput`, `rotatingFileOutput`, `AsyncFileOutput`, `AsyncRotatingFileOutput`) переезжают в `package:structured_log/io.dart`; главная библиотека — без `dart:io`. Выходы с ротацией считают размер в памяти. `structured_log_flutter`: `debugPrintOutput` (одна строка, без ANSI, через `debugPrint`); `LogBuffer` хранит записи в `ListQueue` и уведомляет не чаще раза за ход цикла событий.

## Capabilities

### New Capabilities
- `structured-log-core`: контракт ядра `structured_log` — изоляция вызова лога, безопасная сериализация, метки времени, ранняя фильтрация, параметры ошибки, ленивая конфигурация, форматтеры, раскладка библиотек под платформы. До этой заявки у ядра основной спеки не было.
- `remote-sync-entry-encoding`: как `structured_log_remote_sync` кодирует записи и чем платит за некодируемую. Отдельная капабилити, потому что спека отправителя (`structured-log-http-sender`) живёт в открытой заявке `add-structured-log-server`, а не в `specs/`.

### Modified Capabilities
- `dio-log-interceptor`: тела маскируются по именам полей до сериализации.
- `http-client-logging`: строковые тела JSON/form маскируются по именам полей.
- `flutter-log-viewer-core`: пакетное уведомление `LogBuffer`, однострочный выход `debugPrintOutput`.

## Impact

- `emb/structured_log` → `0.3.0` (ломающие: `io.dart`, UTC по умолчанию, ленивая конфигурация). Версию и `CHANGELOG.md` пишет `melos version` по Conventional Commits — вручную не трогаются.
- Каскад констрейнтов `structured_log: ^0.3.0` во всех пакетах `emb/`, в сервере и admin-клиенте; сервер (`logging/setup.dart`, `AsyncRotatingFileOutput`) добавляет `import 'package:structured_log/io.dart'`.
- `emb/structured_log_remote_sync`, `emb/structured_log_dio`, `emb/structured_log_http_client`, `emb/structured_log_flutter` — правки кода, тестов, README (EN/RU).
- `docs/` (`technology-stack`, `embedding-guide`), сайт перегенерируется скриптом, `AGENTS.md`.
- Сервер: правок приёма нет — UTC-метки он уже разбирает верно; меняется только то, что приходит.
