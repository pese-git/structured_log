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
- [lib/src/processors.dart](lib/src/processors.dart) — процессоры, трансформирующие запись лога.
- [lib/src/formatters.dart](lib/src/formatters.dart) — функции вывода (консоль, файл, ротация файлов).
- [test/structlog_test.dart](test/structlog_test.dart) — набор тестов.
- [example/main.dart](example/main.dart) — рабочий пример использования.

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
  dry-run — файлы (`pubspec.yaml`, `CHANGELOG.md`) переписываются на диске в любом случае,
  причём `CHANGELOG.md` перезаписывается в собственном формате melos (conventional-changelog),
  а не в принятом здесь Keep a Changelog. Поэтому версию и `CHANGELOG.md` в этом репозитории
  правим вручную, сохраняя существующий формат, а не через `melos version`.

## Перед завершением изменения

1. `dart analyze` — не должно быть замечаний.
2. `dart test` — все тесты должны проходить.
3. `dart format --set-exit-if-changed .` — код должен быть отформатирован.
4. При изменении публичного поведения обновлять [README.md](README.md) / [README.ru.md](README.ru.md) и [CHANGELOG.md](CHANGELOG.md).
