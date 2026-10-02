## 1. Ядро: изоляция и сериализация

- [ ] 1.1 Внутренний репортёр `reportInternalError` с условным импортом (`dart.library.io` → `stderr`, иначе `print`), сам вызов под `try` (decision 4); заменить им прямые `stderr.writeln` в `logger.dart` и `async_file_output.dart`
- [ ] 1.2 `encodeLogEntry` (`lib/src/encoding.dart`, экспорт из barrel-файла): `toEncodable` по decision 3, заглушка `encoding_failed` на цикле/сбое
- [ ] 1.3 Перевести `defaultOutput`, `coloredConsoleOutput`, файловые выходы (синхронные и асинхронные) на `encodeLogEntry`
- [ ] 1.4 Изоляция процессоров в `tryLog`: заглушка `processor_failed` по decision 1, весь `tryLog` под внешним `try` (склейка, процессоры, репортёр)
- [ ] 1.5 `redactKeys`: перенос циклов (`'<cycle>'`, множество посещённых по идентичности), контракт «тот же объект» сохранён
- [ ] 1.6 `TimestampMode` (`utc` по умолчанию, `localWithOffset` со смещением `±HH:MM`) в `StructlogConfiguration`/`configure` (decision 5)
- [ ] 1.7 Тесты на каждый сценарий `specs/structured-log-core/spec.md` из этого раздела: бросивший процессор (вызов не бросает, заглушка без значения), `StackOverflowError` из процессора, несериализуемые значения в каждом встроенном выходе, цикл с маскированием и без, бросающий `toString()`, обе метки времени (локальная — с подменой часового пояса через `TZ` в отдельном процессе или через инъекцию часов), сломанный выход + бросающий репортёр. Мутацией проверить: снятие внешнего `try`, доставку исходной записи вместо заглушки

## 2. Ядро: API

- [ ] 2.1 `BoundLogger.isEnabled(level, {category})` и ранний выход по уровню в начале `tryLog` (decision 6); оговорка про процессоры с побочными эффектами в доке `Processor`
- [ ] 2.2 Параметры `error`/`stackTrace` у `tryLog` и всех методов уровня → `error`/`error_type`/`stack_trace` (decision 7)
- [ ] 2.3 Ленивая конфигурация: `BoundLogger` без явной конфигурации читает `StructlogConfiguration.current` и `initialContext` на каждой записи (decision 8); `bind`/`unbind`/`withCorrelation` сохраняют режим родителя; обновить доку `getLogger`/`configure`, убрать фразу «call getLogger again»
- [ ] 2.4 `jsonLineOutput`, `logfmtOutput`; экранирование logfmt по decision 10 в общем помощнике, им же пользуется `logfmtRenderer`
- [ ] 2.5 `@Deprecated` на `jsonRenderer`, `logfmtRenderer`, `addLogLevel`, `addTimestamp`; рендереры переходят на `encodeLogEntry`
- [ ] 2.6 Тесты на сценарии раздела: `trace` без принимающего sink'а (процессор-счётчик), `isEnabled` с категорией, ошибка параметрами и перекрытие ключа `context`, логгер в `static final` до `configure`, явная конфигурация не следует за `current`, logfmt-инъекция (кавычка, `\n`, `=`, управляющий символ, ключ с пробелом). Мутацией проверить ранний выход и экранирование `\n`
- [ ] 2.7 Прогнать тесты всех пакетов, зависящих от ядра по пути (`melos bootstrap` + `melos run test`): ленивая конфигурация и UTC меняют поведение без ошибки компиляции

## 3. Ядро: платформы

- [ ] 3.1 `lib/io.dart`: `fileOutput`, `rotatingFileOutput`, `AsyncFileOutput`, `AsyncRotatingFileOutput`; убрать их из `structured_log.dart` (decision 12)
- [ ] 3.2 Тест-страж: обход импортов от `lib/structured_log.dart` не встречает `dart:io`
- [ ] 3.3 Размер файла в памяти для `rotatingFileOutput`/`AsyncRotatingFileOutput` (decision 13); тест «ротация по учтённому размеру» и тест, что на каждую запись нет `exists`/`length` (через счётчик в подставной `IOOverrides`)
- [ ] 3.4 `test` в CI на трёх ОС проходит (ротация — ОС-чувствительна)
- [ ] 3.5 Сервер: `import 'package:structured_log/io.dart'` в `lib/src/logging/setup.dart`; прогнать его тесты, включая `integration`

## 4. structured_log_remote_sync

- [ ] 4.1 Кодирование при постановке в очередь: буфер строк, пакет — `'[' + join(',') + ']'`; некодируемая запись отбрасывается поштучно с сообщением репортёру; `_reportToStderr` → репортёр ядра
- [ ] 4.2 Тесты на сценарии `specs/remote-sync-entry-encoding/spec.md` (подставной `BatchSender` и настоящий `HttpServer`); мутацией проверить, что откат к `jsonEncode(entries)` краснеет
- [ ] 4.3 Лимит буфера по-прежнему в записях; оценить и задокументировать память строки против карты, если отличие заметно

## 5. Маскирование тел

- [ ] 5.1 `structured_log_dio`: `redactedBodyFields` (по умолчанию `defaultSensitiveKeys`), маскирование `Map`/`List` через `redactKeys` ядра до `describeBody`, разбор JSON/form-строк по `Content-Type`, `'<unparseable body>'`, `logUnrecognizedBodies` (decision 11)
- [ ] 5.2 `structured_log_http_client`: то же для строковых тел запроса и захваченного начала тела ответа; читатель получает тело без изменений
- [ ] 5.3 Тесты на сценарии `specs/dio-log-interceptor/spec.md` и `specs/http-client-logging/spec.md`: тело запроса токена, form-строкой, JSON-строкой, `*+json`, вложенный секрет, неразбираемое тело, строка неизвестного типа, свой `describeBody` видит замаскированное, читатель получает исходное. Мутацией проверить обе ветки (структура и строка) в обоих пакетах
- [ ] 5.4 `structured_log_bloc`: только документация — `describe`, возвращающий `Map`, проходит через `redactKeys`; пример в README (EN/RU)

## 6. structured_log_flutter

- [ ] 6.1 `LogBuffer`: `ListQueue`, публикация снимка через `scheduleMicrotask`, синхронный `clear()` (decision 14)
- [ ] 6.2 `debugPrintOutput` (decision 15) с экранированием из ядра
- [ ] 6.3 Тесты на сценарии `specs/flutter-log-viewer-core/spec.md`: всплеск из 100 записей — одно уведомление, ёмкость соблюдается, снимок неизменяем, `clear()` синхронен, `debugPrintOutput` без `\n` и `\x1B`; виджет-тесты скинов (`material`/`fluent`/`cupertino`) проходят с асинхронной публикацией (`pump` после захвата)

## 7. Документация и выпуск

- [ ] 7.1 README ядра (EN/RU): раздел миграции на `0.3.0` (`io.dart`, UTC, ленивая конфигурация, рендереры → выходы), параметры `error`/`stackTrace`, `isEnabled`, `encodeLogEntry`
- [ ] 7.2 README `_remote_sync`, `_dio`, `_http_client`, `_flutter` (EN/RU)
- [ ] 7.3 `docs/architecture/technology-stack.md`/`.ru.md`, `docs/guides/embedding-guide.md`/`.ru.md`, `emb/structured_log/doc/ARCHITECTURE.md`/`.ru.md` (жизненный цикл вызова: ранний выход, изоляция процессоров, кодирование); сайт — перегенерацией `site/scripts/migrate_docs.py`
- [ ] 7.4 `AGENTS.md`: раскладка `io.dart`, решения про fail-closed и кодирование при постановке в очередь
- [ ] 7.5 Констрейнты `structured_log: ^0.3.0` во всех зависимых пакетах; коммиты с `BREAKING CHANGE:` там, где decisions 5, 8, 12; `CHANGELOG.md` вручную не трогать
- [ ] 7.6 Пороги в `tool/coverage_floors.json` не опускать; поднять, если измеренное покрытие выросло
- [ ] 7.7 CI зелёный на всех джобах
