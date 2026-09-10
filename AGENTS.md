# AGENTS.md

Инструкции для AI-агентов, работающих в этом репозитории.

## Проект

`structured_log` — структурированное логирование для Dart, вдохновлено Python `structlog`.
Без сторонних зависимостей во время выполнения (кроме `meta`). Управляется через Melos + FVM
(single-package workspace; Melos используется для скриптов, а не для оркестрации нескольких пакетов).

## Структура

- [lib/structured_log.dart](lib/structured_log.dart) — публичный barrel-файл экспорта.
- [lib/src/logger.dart](lib/src/logger.dart) — `BoundLogger`, `LogLevel`, `getLogger()`.
- [lib/src/configuration.dart](lib/src/configuration.dart) — глобальный синглтон `StructlogConfiguration`.
- [lib/src/sink.dart](lib/src/sink.dart) — `LogSink`, мультивывод с независимой фильтрацией по уровню/категории и runtime-переключением.
- [lib/src/correlation.dart](lib/src/correlation.dart) — `LogCorrelation`, типизированные id (session/request/connection/tool-call/message/operation) для `BoundLogger.withCorrelation()`.
- [lib/src/processors.dart](lib/src/processors.dart) — процессоры, трансформирующие запись лога.
- [lib/src/formatters.dart](lib/src/formatters.dart) — функции вывода (консоль, файл, ротация файлов) — синхронные.
- [lib/src/async_file_output.dart](lib/src/async_file_output.dart) — `AsyncFileOutput`/`AsyncRotatingFileOutput`, неблокирующие аналоги файлового вывода с сериализованной очередью записи.
- [test/structlog_test.dart](test/structlog_test.dart) — модульные тесты по компонентам.
- [test/integration_test.dart](test/integration_test.dart) — интеграционные тесты, проверяющие пакет как целую систему на реальных файлах.
- [example/main.dart](example/main.dart) — рабочий пример использования.
- [doc/ARCHITECTURE.md](doc/ARCHITECTURE.md) / [doc/ARCHITECTURE.ru.md](doc/ARCHITECTURE.ru.md) — внутренний дизайн для контрибьюторов с mermaid-диаграммами (жизненный цикл лог-вызова, мульти-синк роутинг).

## Команды

Запускаются через `melos run <script>` (см. [melos.yaml](melos.yaml)) либо напрямую через `dart`:

```bash
dart analyze
dart format .
dart format --set-exit-if-changed .   # format:check
dart test
dart test --coverage=coverage
dart run example/main.dart
```

`melos run lint` запускает analyze + format:check вместе; `melos run build` — `pub get` + analyze.

## Соглашения

- Публичный API экспортируется только через [lib/structured_log.dart](lib/structured_log.dart); новые публичные символы добавлять туда же.
- `BoundLogger.bind()` / `unbind()` иммутабельны — всегда возвращают новый экземпляр, никогда не мутируют `_context` на месте.
- Процессоры имеют тип `Map<String, dynamic>? Function(Map<String, dynamic> entry)`; возврат `null` отбрасывает запись. Новые процессоры должны быть чистыми функциями и не зависеть от порядка выполнения, если это не документировано отдельно.
- `StructlogConfiguration` — глобальное изменяемое состояние (`_current`); тесты, вызывающие `configure()`, обязаны делать `reset()` в `tearDown`, чтобы не влиять на другие тесты.
- Никаких сторонних runtime-зависимостей — сохранять это, если явно не попросили иначе.
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

## CI

[.github/workflows/ci.yml](.github/workflows/ci.yml) запускается на push/PR
в `master`/`develop` и на `workflow_dispatch`: `dart format --set-exit-if-changed`,
`dart analyze`, `dart test` и `dart run example/main.dart` — на
`ubuntu-latest`/`macos-latest`/`windows-latest` (важно именно на всех трёх,
т.к. `async_file_output.dart` и ротация делают реальные
rename/delete/exists на файловой системе, а её поведение отличается между
POSIX и Windows). Использует `dart-lang/setup-dart` (канал `stable`), а не
FVM/Flutter — пакет не зависит от Flutter, полноценный SDK через FVM в CI
не нужен.

## Перед завершением изменения

1. `dart analyze` — не должно быть замечаний.
2. `dart test` — все тесты должны проходить.
3. `dart format --set-exit-if-changed .` — код должен быть отформатирован.
4. При изменении публичного поведения обновлять [README.md](README.md) / [README.ru.md](README.ru.md) (но не `CHANGELOG.md` — см. «Коммиты и версионирование»).
5. CI ([.github/workflows/ci.yml](.github/workflows/ci.yml)) должен быть зелёным на всех трёх ОС.
