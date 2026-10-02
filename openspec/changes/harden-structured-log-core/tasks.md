## 1. Ядро: изоляция и сериализация

- [x] 1.1 Внутренний репортёр `reportInternalError` с условным импортом (`dart.library.io` → `stderr`, иначе `print`), сам вызов под `try` (decision 4); заменить им прямые `stderr.writeln` в `logger.dart` и `async_file_output.dart` — `lib/src/report.dart` (+ `report_io.dart`/`report_print.dart`); проверено и сборкой `dart compile js` под node: оба сбоя (процессор и sink) ушли через `print`, вызов вернулся
- [x] 1.2 `encodeLogEntry` (`lib/src/encoding.dart`, экспорт из barrel-файла): `toEncodable` по decision 3, заглушка `encoding_failed` на цикле/сбое — `encodeLogEntry` экспортирован, `identifyingFields`/`describeValue` остались внутренними
- [x] 1.3 Перевести `defaultOutput`, `coloredConsoleOutput`, файловые выходы (синхронные и асинхронные) на `encodeLogEntry`
- [x] 1.4 Изоляция процессоров в `tryLog`: заглушка `processor_failed` по decision 1, весь `tryLog` под внешним `try` (склейка, процессоры, репортёр) — плюс `accepts` бросившего подкласса `LogSink` перенесён внутрь защиты каждого sink'а (найдено тестом: внешний `try` обрывал рассылку остальным), а не-строковая `category` больше не роняет вызов `as String?`
- [x] 1.5 `redactKeys`: перенос циклов (`'<cycle>'`, множество посещённых по идентичности), контракт «тот же объект» сохранён — путь хранится стеком предков, а не множеством посещённых: объект, достижимый по двум путям, циклом не считается (мутацией проверено)
- [x] 1.6 `TimestampMode` (`utc` по умолчанию, `localWithOffset` со смещением `±HH:MM`) в `StructlogConfiguration`/`configure` (decision 5)
- [x] 1.7 Тесты на каждый сценарий `specs/structured-log-core/spec.md` из этого раздела: бросивший процессор (вызов не бросает, заглушка без значения), `StackOverflowError` из процессора, несериализуемые значения в каждом встроенном выходе, цикл с маскированием и без, бросающий `toString()`, обе метки времени (локальная — с подменой часового пояса через `TZ` в отдельном процессе или через инъекцию часов), сломанный выход + бросающий репортёр. Мутацией проверить: снятие внешнего `try`, доставку исходной записи вместо заглушки — `test/reliability_test.dart`, 37 тестов. Локальная метка проверяется без подмены пояса: смещение сверяется с `timeZoneOffset` самой метки; дополнительно прогнано под `TZ=America/St_Johns` и `TZ=Asia/Kathmandu`. Мутациями убиты: внешний `try` (выжил при первой редакции — добавлен тест на карту, которую нельзя прочитать), доставка исходной записи вместо заглушки, глобальное множество посещённых в `redactKeys`. Покрытие ядра — 100 % (273 строки). Потребители зелёные против локальной копии: `remote_sync` 43, `bloc` 16, `dio` 22, `http_client` 31, `cherrypick` 17, `flutter` 22, сервер 1072 (без `postgres`)

## 2. Ядро: API

- [x] 2.1 `BoundLogger.isEnabled(level, {category})` и ранний выход по уровню в начале `tryLog` (decision 6); оговорка про процессоры с побочными эффектами в доке `Processor` — ранний выход смотрит только `enabled`/`minLevel`; `isEnabled` с категорией спрашивает `accepts`, и бросивший `accepts` считается принимающим
- [x] 2.2 Параметры `error`/`stackTrace` у `tryLog` и всех методов уровня → `error`/`error_type`/`stack_trace` (decision 7)
- [x] 2.3 Ленивая конфигурация: `BoundLogger` без явной конфигурации читает `StructlogConfiguration.current` и `initialContext` на каждой записи (decision 8); `bind`/`unbind`/`withCorrelation` сохраняют режим родителя; обновить доку `getLogger`/`configure`, убрать фразу «call getLogger again» — публичный конструктор `BoundLogger(config)` по-прежнему закрепляет конфигурацию (и, как раньше, не подмешивает `initialContext`); следующий режим — у приватного `BoundLogger._(null, …)`, его отдаёт `getLogger`
- [x] 2.4 `jsonLineOutput`, `logfmtOutput`; экранирование logfmt по decision 10 в общем помощнике, им же пользуется `logfmtRenderer` — `formatLogfmt` публичный: им же будет пользоваться `debugPrintOutput` (раздел 6)
- [x] 2.5 `@Deprecated` на `jsonRenderer`, `logfmtRenderer`, `addLogLevel`, `addTimestamp`; рендереры переходят на `encodeLogEntry`
- [x] 2.6 Тесты на сценарии раздела: `trace` без принимающего sink'а (процессор-счётчик), `isEnabled` с категорией, ошибка параметрами и перекрытие ключа `context`, логгер в `static final` до `configure`, явная конфигурация не следует за `current`, logfmt-инъекция (кавычка, `\n`, `=`, управляющий символ, ключ с пробелом). Мутацией проверить ранний выход и экранирование `\n` — `test/api_test.dart`, 23 теста; `structlog_test.dart` гасит `deprecated_member_use_from_same_package` — устаревшие процессоры там и проверяются. Мутациями убиты: ранний выход, экранирование `\n`, ленивое чтение `initialContext`. Покрытие ядра — 100 % (320 строк)
- [x] 2.7 Прогнать тесты всех пакетов, зависящих от ядра по пути (`melos bootstrap` + `melos run test`): ленивая конфигурация и UTC меняют поведение без ошибки компиляции — против локальной копии: `remote_sync` 43, `bloc` 16, `dio` 22, `http_client` 31, `cherrypick` 17, `flutter` 22, `go_router` 23, сервер 1072 (без `postgres`), admin-клиент 449 — все зелёные

## 3. Ядро: платформы

- [x] 3.1 `lib/io.dart`: `fileOutput`, `rotatingFileOutput`, `AsyncFileOutput`, `AsyncRotatingFileOutput`; убрать их из `structured_log.dart` (decision 12) — `fileOutput`/`rotatingFileOutput` переехали из `formatters.dart` в `lib/src/file_output.dart`; `io.dart` экспортирует его и `async_file_output.dart`. dartdoc-ссылки на них из главной библиотеки и из `structured_log_flutter` (`LogBuffer`) переписаны текстом — иначе они висели бы
- [x] 3.2 Тест-страж: обход импортов от `lib/structured_log.dart` не встречает `dart:io` — `test/io_test.dart`: обход `import`/`export` от `lib/structured_log.dart`, условный импорт — по ветке по умолчанию (её и берёт web); до переноса страж называл `formatters.dart` и `async_file_output.dart`
- [x] 3.3 Размер файла в памяти для `rotatingFileOutput`/`AsyncRotatingFileOutput` (decision 13); тест «ротация по учтённому размеру» и тест, что на каждую запись нет `exists`/`length` (через счётчик в подставной `IOOverrides`) — запись теперь байтами (`utf8.encode` один раз, `writeAsBytes`), размер прибавляется после успешной записи. Подставная `File` через `IOOverrides.createFile` считает `exists`/`length`: ноль на 10 записей. Мутациями убиты: несброс счётчика после ротации (синхронно и асинхронно — для этого тестам понадобилась четвёртая запись), учёт до записи, неучёт существующего содержимого. Покрытие ядра — 100 %
- [ ] 3.4 `test` в CI на трёх ОС проходит (ротация — ОС-чувствительна) — локально проверено только на macOS; ждёт прогона CI на PR
- [x] 3.5 Сервер: `import 'package:structured_log/io.dart'` в `lib/src/logging/setup.dart`; прогнать его тесты, включая `integration` — плюс сервер собирается и в Docker: образ подставляет ядро по пути (`pubspec_overrides.yaml` в `Dockerfile`), так что импорт `io.dart` не ждёт публикации `0.3.0`. Сервер 1072 (без `postgres`), `flutter` 22, чистые Dart-пакеты — зелёные

## 4. structured_log_remote_sync

- [x] 4.1 Кодирование при постановке в очередь: буфер строк, пакет — `'[' + join(',') + ']'`; некодируемая запись отбрасывается поштучно с сообщением репортёру; `_reportToStderr` → репортёр ядра — `_reportToStderr` не заменён репортёром ядра: тот не экспортирован, а пакет и так только для `dart:io` (транспорт — `HttpClient`); вместо этого запись в `stderr` обёрнута в `try`. `BatchSender` сохранён — см. decision 16
- [x] 4.2 Тесты на сценарии `specs/remote-sync-entry-encoding/spec.md` (подставной `BatchSender` и настоящий `HttpServer`); мутацией проверить, что откат к `jsonEncode(entries)` краснеет — `test/entry_encoding_test.dart`, 5 тестов. До правки настоящий сервер не получил тела вовсе: весь пакет из 10 записей пропал из-за одной. Мутациями убиты: голый `jsonEncode` при постановке в очередь, снятая защита кодирования, пакет без обёртки в массив. Покрытие — 94,9 % (было 94,6). Прослойка `structured_log_http` и `packages/e2e` (22, через настоящий процесс сервера) — зелёные
- [x] 4.3 Лимит буфера по-прежнему в записях; оценить и задокументировать память строки против карты, если отличие заметно — по RSS на 10 000 типичных записей (`http_response`, 10 полей): строками около 4–5 МБ, картами — 25–35 МБ (замер грубый, JIT шумит, но разница в разы устойчива). Лимит остаётся в записях; отдельной документации не потребовалось — памяти стало меньше

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
