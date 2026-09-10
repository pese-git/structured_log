# AGENTS.md

Инструкции для AI-агентов, работающих в этом репозитории.

## Проект

Репозиторий — multi-package workspace на Melos + FVM с плоской раскладкой пакетов
(каждый пакет — отдельная директория в корне репозитория, перечисленная по имени
в [melos.yaml](melos.yaml); без вложенности вроде `packages/<name>/`) — по образцу
[cherrypick](https://github.com/pese-git/cherrypick) того же автора.

Три пакета:

- [structured_log/](structured_log/) — структурированное логирование для Dart, вдохновлено
  Python `structlog`, без сторонних runtime-зависимостей (кроме `meta`). Опубликован на pub.dev.
- [structured_log_flutter/](structured_log_flutter/) — headless-ядро для in-app просмотра логов
  во Flutter (`LogBuffer`, `LogViewerController`); не зависит ни от какой конкретной дизайн-системы.
- [structured_log_material/](structured_log_material/) — Material 3 виджет просмотрщика логов
  поверх `structured_log_flutter`.

Оба Flutter-пакета пока не опубликованы (`0.1.0-dev.1`, `publish_to: none` у `structured_log_material`
из-за path-зависимости на неопубликованный `structured_log_flutter`). История и обоснование решений —
в [openspec/changes/add-structured-log-flutter/](openspec/changes/add-structured-log-flutter/)
(`proposal.md`/`design.md`/`specs/`/`tasks.md` — по `tasks.md` можно свериться, что уже сделано).

## Структура

Верхний уровень репозитория:

- [structured_log/](structured_log/) — пакет структурированного логирования (см. ниже).
- [structured_log_flutter/](structured_log_flutter/) — headless-ядро просмотрщика логов (см. ниже).
- [structured_log_material/](structured_log_material/) — Material-скин просмотрщика логов (см. ниже).
- [melos.yaml](melos.yaml) — манифест workspace и общие скрипты (analyze/format/test/lint/build).
- [pubspec.yaml](pubspec.yaml) — корневой pubspec workspace (`publish_to: none`, не публикуется); нужен
  только для того, чтобы `dart run melos <cmd>` резолвил `melos` как dev-зависимость — сам по себе
  не является пакетом workspace и не перечислен в `packages:` в `melos.yaml`.
- [openspec/](openspec/) — артефакты OpenSpec (proposal/design/specs/tasks) для change-заявок.
- [.github/workflows/ci.yml](.github/workflows/ci.yml) — CI.
- [LICENSE](LICENSE) — лицензия репозитория; копия лежит также внутри `structured_log/`
  (и будет копироваться в каждый новый пакет), так как `dart pub publish` пакует только
  содержимое директории пакета.

Внутри [structured_log/](structured_log/):

- [structured_log/lib/structured_log.dart](structured_log/lib/structured_log.dart) — публичный barrel-файл экспорта.
- [structured_log/lib/src/logger.dart](structured_log/lib/src/logger.dart) — `BoundLogger`, `LogLevel`, `getLogger()`.
- [structured_log/lib/src/configuration.dart](structured_log/lib/src/configuration.dart) — глобальный синглтон `StructlogConfiguration`.
- [structured_log/lib/src/sink.dart](structured_log/lib/src/sink.dart) — `LogSink`, мультивывод с независимой фильтрацией по уровню/категории и runtime-переключением.
- [structured_log/lib/src/correlation.dart](structured_log/lib/src/correlation.dart) — `LogCorrelation`, типизированные id (session/request/connection/tool-call/message/operation) для `BoundLogger.withCorrelation()`.
- [structured_log/lib/src/processors.dart](structured_log/lib/src/processors.dart) — процессоры, трансформирующие запись лога.
- [structured_log/lib/src/formatters.dart](structured_log/lib/src/formatters.dart) — функции вывода (консоль, файл, ротация файлов) — синхронные.
- [structured_log/lib/src/async_file_output.dart](structured_log/lib/src/async_file_output.dart) — `AsyncFileOutput`/`AsyncRotatingFileOutput`, неблокирующие аналоги файлового вывода с сериализованной очередью записи.
- [structured_log/test/structlog_test.dart](structured_log/test/structlog_test.dart) — модульные тесты по компонентам.
- [structured_log/test/integration_test.dart](structured_log/test/integration_test.dart) — интеграционные тесты, проверяющие пакет как целую систему на реальных файлах.
- [structured_log/example/main.dart](structured_log/example/main.dart) — рабочий пример использования.
- [structured_log/doc/ARCHITECTURE.md](structured_log/doc/ARCHITECTURE.md) / [structured_log/doc/ARCHITECTURE.ru.md](structured_log/doc/ARCHITECTURE.ru.md) — внутренний дизайн для контрибьюторов с mermaid-диаграммами (жизненный цикл лог-вызова, мульти-синк роутинг).

Внутри [structured_log_flutter/](structured_log_flutter/):

- [structured_log_flutter/lib/structured_log_flutter.dart](structured_log_flutter/lib/structured_log_flutter.dart) — barrel-файл экспорта.
- [structured_log_flutter/lib/src/log_buffer.dart](structured_log_flutter/lib/src/log_buffer.dart) — `LogBuffer`: кольцевой буфер, `capture()` подключается как `OutputFunction`/`LogSink.output`, отдаёт записи как `ValueListenable`.
- [structured_log_flutter/lib/src/log_viewer_controller.dart](structured_log_flutter/lib/src/log_viewer_controller.dart) — `LogViewerController` (`ChangeNotifier`): фильтры по уровню/категории/поиску, пауза, `clear()`; плюс публичная `logLevelOf()`.
- [structured_log_flutter/test/](structured_log_flutter/test/) — тесты (`flutter test`) на `LogBuffer` и `LogViewerController`.

Внутри [structured_log_material/](structured_log_material/):

- [structured_log_material/lib/structured_log_material.dart](structured_log_material/lib/structured_log_material.dart) — barrel-файл экспорта.
- [structured_log_material/lib/src/material_log_viewer_page.dart](structured_log_material/lib/src/material_log_viewer_page.dart) — `MaterialLogViewerPage`: экран со списком, поиском, чипами фильтра по уровню, паузой/очисткой.
- [structured_log_material/lib/src/log_entry_tile.dart](structured_log_material/lib/src/log_entry_tile.dart) — `LogEntryTile`: строка списка (уровень/время/event/category).
- [structured_log_material/lib/src/log_entry_detail_sheet.dart](structured_log_material/lib/src/log_entry_detail_sheet.dart) — `LogEntryDetailSheet`: bottom sheet с полным контекстом записи и копированием.
- [structured_log_material/lib/src/log_viewer_empty_state.dart](structured_log_material/lib/src/log_viewer_empty_state.dart) — `LogViewerEmptyState`: «логов ещё нет» / «нет по фильтру».
- [structured_log_material/lib/src/log_level_colors.dart](structured_log_material/lib/src/log_level_colors.dart) — `logLevelColor()`, единственный источник цветов уровня лога.
- [structured_log_material/test/](structured_log_material/test/) — виджет-тесты (`flutter test`).
- [structured_log_material/example/](structured_log_material/example/) — полноценное Flutter-приложение (`structured_log_material_example` в `melos.yaml`), запускается через `flutter run -d chrome` (или `-d web-server`) из этой директории; поддерживает web.

## Команды

Запускаются через `melos run <script>` из корня репозитория (см. [melos.yaml](melos.yaml)) —
скрипты, кроме `clean`, определены через `exec:`/`steps:` и выполняются в директории каждого
пакета workspace. Если глобально активированный `melos` недоступен/сломан (например, конфликт
версии Dart SDK со снапшотом бинаря), используйте `dart run melos <cmd>` — корневой
[pubspec.yaml](pubspec.yaml) как раз для этого держит `melos` в dev-зависимостях:

```bash
dart run melos bootstrap
dart run melos run analyze
dart run melos run test
dart run melos run lint
```

Для прямых вызовов `dart` нужно сначала зайти в директорию пакета:

```bash
cd structured_log

dart analyze
dart format .
dart format --set-exit-if-changed .   # format:check
dart test
dart test --coverage=coverage
dart run example/main.dart
```

`melos run lint` запускает analyze + format:check вместе; `melos run build` — `pub get` + analyze;
`melos run example` — пример конкретно для `structured_log`.

## Соглашения

- Публичный API `structured_log` экспортируется только через [structured_log/lib/structured_log.dart](structured_log/lib/structured_log.dart); новые публичные символы добавлять туда же.
- `BoundLogger.bind()` / `unbind()` иммутабельны — всегда возвращают новый экземпляр, никогда не мутируют `_context` на месте.
- Процессоры имеют тип `Map<String, dynamic>? Function(Map<String, dynamic> entry)`; возврат `null` отбрасывает запись. Новые процессоры должны быть чистыми функциями и не зависеть от порядка выполнения, если это не документировано отдельно.
- `StructlogConfiguration` — глобальное изменяемое состояние (`_current`); тесты, вызывающие `configure()`, обязаны делать `reset()` в `tearDown`, чтобы не влиять на другие тесты.
- Никаких сторонних runtime-зависимостей у `structured_log` — сохранять это, если явно не попросили иначе. Flutter-пакеты (`structured_log_flutter`/`structured_log_material`), когда появятся, этому ограничению не подчиняются, но `structured_log_flutter` сам не должен зависеть от конкретной дизайн-системы (Material/Cupertino/Fluent) — см. design.md в [openspec/changes/add-structured-log-flutter/](openspec/changes/add-structured-log-flutter/).
- Форматирование должно строго соответствовать существующему (`dart format .` перед завершением любого изменения).
- Артефакты OpenSpec ([openspec/changes/](openspec/changes/)) пишутся на русском языке — кроме ключевых слов
  и идентификаторов (заголовки секций типа `## Why`/`## What Changes`, имена пакетов/капабилити,
  имена символов кода, флаги команд и т.п., которые остаются как есть, не переводятся).

## Коммиты и версионирование

- Сообщения коммитов пишутся в формате [Conventional Commits](https://www.conventionalcommits.org/)
  (`feat:`, `fix:`, `docs:`, `chore:`, `refactor:`, `perf:`, `test:`, `build:`, `ci:`, `revert:`;
  ломающее изменение — `!` после типа или футер `BREAKING CHANGE:`). Это нужно, чтобы
  `melos version` мог автоматически определять нужный semver-бамп по истории коммитов.
- `melos version` ищет точку отсчёта по git-тегу вида `<package>-v<version>`
  (например, `structured_log-v0.2.0-dev.1`) и версионирует только коммиты после него —
  без такого тега или без Conventional Commits в истории он не находит, что версионировать.
- `melos version -V <package>:<major|patch|minor|build|exactVersion>` — ручной бамп версии.
  **Важно:** флаги `--no-git-commit-version`/`--no-git-tag-version` НЕ делают команду
  dry-run — файлы (`pubspec.yaml`, `CHANGELOG.md`) переписываются на диске в любом случае.
- **`CHANGELOG.md` вручную не редактировать никогда** — ни для добавления записей о
  новой фиче/фиксе, ни для «уборки» после `melos version` (даже если он переписал файл
  в своём собственном формате поверх предыдущего содержимого). Версию и changelog меняет
  только `melos version` — это осознанное решение мейнтейнера, не пробел в процессе.
- Каждый пакет workspace версионируется независимо — своя линия git-тегов, свой `CHANGELOG.md`.

## CI

[.github/workflows/ci.yml](.github/workflows/ci.yml) запускается на push/PR
в `master`/`develop` и на `workflow_dispatch`: `dart format --set-exit-if-changed`,
`dart analyze`, `dart test` и `dart run example/main.dart` — на
`ubuntu-latest`/`macos-latest`/`windows-latest` (важно именно на всех трёх,
т.к. `async_file_output.dart` и ротация делают реальные
rename/delete/exists на файловой системе, а её поведение отличается между
POSIX и Windows), с `working-directory: structured_log`. Использует
`dart-lang/setup-dart` (канал `stable`), а не FVM/Flutter — `structured_log`
не зависит от Flutter, полноценный SDK через FVM в CI не нужен. Когда появятся
Flutter-пакеты, для них потребуется отдельная джоба/ветка с Flutter SDK.

## Перед завершением изменения

1. `dart analyze` — не должно быть замечаний.
2. `dart test` — все тесты должны проходить.
3. `dart format --set-exit-if-changed .` — код должен быть отформатирован.
4. При изменении публичного поведения пакета обновлять его `README.md`/`README.ru.md`
   ([structured_log/](structured_log/README.md), [structured_log_flutter/](structured_log_flutter/README.md),
   [structured_log_material/](structured_log_material/README.md)) — но не `CHANGELOG.md`
   (см. «Коммиты и версионирование»).
5. CI ([.github/workflows/ci.yml](.github/workflows/ci.yml)) должен быть зелёным на всех трёх ОС.
