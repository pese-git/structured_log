# emb/structured_log — заметки для агентов

Дополняет корневой [AGENTS.md](../../AGENTS.md) (проект, команды, соглашения, версионирование, CI). Подгружается, когда работа идёт в этом каталоге; `CLAUDE.md` рядом — симлинк на этот файл.
- [lib/structured_log.dart](lib/structured_log.dart) — публичный barrel-файл экспорта.
- [lib/src/logger.dart](lib/src/logger.dart) — `BoundLogger`, `LogLevel`, `getLogger()`.
- [lib/src/configuration.dart](lib/src/configuration.dart) — глобальный синглтон `StructlogConfiguration`.
- [lib/src/sink.dart](lib/src/sink.dart) — `LogSink`, мультивывод с независимой фильтрацией по уровню/категории и runtime-переключением.
- [lib/src/correlation.dart](lib/src/correlation.dart) — `LogCorrelation`, типизированные id (session/request/connection/tool-call/message/operation) для `BoundLogger.withCorrelation()`.
- [lib/src/processors.dart](lib/src/processors.dart) — процессоры, трансформирующие запись лога.
- [lib/src/formatters.dart](lib/src/formatters.dart) — консольные выходы (`defaultOutput`, `coloredConsoleOutput`, `jsonLineOutput`, `logfmtOutput`) и `formatLogfmt`; без `dart:io` — файловых выходов здесь больше нет.
- [lib/io.dart](lib/io.dart) — вторая публичная библиотека: файловые выходы, которым нужен
  `dart:io`. Импортируется **вместе** с `structured_log.dart`, а не вместо неё. Условный экспорт
  отвергнут: API главной библиотеки различался бы по платформе, и «нет такого символа» всплывало бы
  только при сборке под web (decision 12 `harden-structured-log-core`). В репозитории её импортирует
  только сервер (`logging/setup.dart`).
- [lib/src/file_output.dart](lib/src/file_output.dart) — `fileOutput`/`rotatingFileOutput`, синхронные. Ротируемый выход держит размер файла в памяти — читает `length` один раз при создании и прибавляет записанные байты, — а не спрашивает файловую систему на каждой записи; внешнюю обрезку файла он не замечает (цена — одна лишняя или запоздалая ротация, не потеря данных).
- [lib/src/async_file_output.dart](lib/src/async_file_output.dart) — `AsyncFileOutput`/`AsyncRotatingFileOutput`, неблокирующие аналоги файлового вывода с сериализованной очередью записи; экспортируются тоже только из `io.dart`.
- [lib/src/encoding.dart](lib/src/encoding.dart) — `encodeLogEntry`, единственный кодировщик записи
  для всех встроенных выходов, `structured_log_remote_sync` и `debugPrintOutput`: `DateTime` →
  ISO-8601 UTC, enum → `name`, `Duration` → микросекунды, `Set` → список, объект с `toJson()` → его
  результат (так делал `jsonEncode` в 0.2.x; собственный `toEncodable` его вызывать перестаёт,
  поэтому `jsonOf` вызывает явно), прочее → `toString()` (бросивший — `'<Type>'`); цикл → заглушка с
  `encoding_failed`. Значение, которое не принял бы `jsonEncode`, стоит одного поля, а не записи.
  Нормализуется только при кодировании — процессоры и `LogBuffer` видят исходные объекты.
- [lib/src/report.dart](lib/src/report.dart) — `reportInternalError`: условный импорт (`report_io.dart` → `stderr`, `report_print.dart` → `print`), потому что на web `stderr.writeln` сам бросает, и аварийная ветка роняла бы вызов, который защищала. Репортёр не бросает никогда.
- [lib/src/timestamp.dart](lib/src/timestamp.dart) — `TimestampMode`: `utc` (по умолчанию, `Z`) или `localWithOffset` (`+03:00`). Прежнего локального формата без смещения нет вовсе: сервер читал его как своё локальное время и смещал записи на разницу поясов.
- **Вызов лога не бросает никогда.** Бросивший процессор → sink'и получают заглушку
  (`event`/`level`/`timestamp`/`logger`/`category` + `processor_failed: <тип>`), процессоры после
  него не выполняются, исходная запись **не** доставляется: бросить мог как раз маскирующий
  процессор, и доставка «как есть» была бы утечкой (fail-closed, decision 1). Текст исключения в
  заглушку не пишется — он может цитировать значение. Сбой `accepts`/`output` одного sink'а
  сообщается и не мешает остальным.
- **`getLogger()` читает `StructlogConfiguration.current` на каждой записи** (sink'и, процессоры, `initialContext`), так что логгер в `static final`, созданный до `configure()`, ему следует. `BoundLogger(config)` с явной конфигурацией по-прежнему её фиксирует (путь для DI и изолированных тестов) и `initialContext` не склеивает. Совет «взять логгер заново после `configure`» больше не нужен.
- **Ранний выход по уровню**: `tryLog` сначала спрашивает `isEnabled(level)` и без включённого sink'а с подходящим `minLevel` не склеивает контекст и не гоняет процессоры. Категорию так проверить нельзя — она известна только после склейки. Следствие: процессор с побочным эффектом (счётчик) не видит записей, которые никто не примет.
- `jsonRenderer`/`logfmtRenderer` (печатали изнутри цепочки процессоров), `addLogLevel` (ничего не делал) и `addTimestamp` (дублировал `tryLog`) — `@Deprecated`; замена рендерерам — выходы `jsonLineOutput`/`logfmtOutput`.
- [test/structlog_test.dart](test/structlog_test.dart) — модульные тесты по компонентам.
- [test/integration_test.dart](test/integration_test.dart) — интеграционные тесты, проверяющие пакет как целую систему на реальных файлах.
- [test/io_test.dart](test/io_test.dart) — страж раскладки: обходит импорты от `lib/structured_log.dart` (условные — по ветке по умолчанию, той, что берёт web) и падает, если достижим `dart:io`; заодно проверяет, что обход дошёл до `formatters.dart`, иначе страж молча ничего бы не сторожил.
- [test/reliability_test.dart](test/reliability_test.dart) / [test/api_test.dart](test/api_test.dart) — изоляция и кодирование / новый API (`isEnabled`, `error`/`stackTrace`, ленивая конфигурация, logfmt); `api_test` гасит `deprecated_member_use_from_same_package` — устаревшие рендереры проверяются, пока не удалены.
- [example/main.dart](example/main.dart) — рабочий пример использования.
- [doc/ARCHITECTURE.md](doc/ARCHITECTURE.md) / [doc/ARCHITECTURE.ru.md](doc/ARCHITECTURE.ru.md) — внутренний дизайн для контрибьюторов с mermaid-диаграммами (жизненный цикл лог-вызова, мульти-синк роутинг).
