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

## Перед завершением изменения

1. `dart analyze` — не должно быть замечаний.
2. `dart test` — все тесты должны проходить.
3. `dart format --set-exit-if-changed .` — код должен быть отформатирован.
4. При изменении публичного поведения обновлять [README.md](README.md) / [README.ru.md](README.ru.md) и [CHANGELOG.md](CHANGELOG.md).
