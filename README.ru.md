[![CI](https://github.com/pese-git/structured_log/actions/workflows/ci.yml/badge.svg)](https://github.com/pese-git/structured_log/actions/workflows/ci.yml)

*Read in [English](README.md).*

# structured_log Workspace

Monorepo на Melos + FVM для структурированного логирования в Dart,
вдохновлённого Python [`structlog`](https://www.structlog.org/), плюс
экосистема in-app просмотра логов для Flutter поверх него.

## Пакеты

- **[`structured_log`](structured_log/)** — базовая библиотека:
  структурированный JSON-лог с привязкой контекста, типизированными
  correlation-полями, процессорами и маршрутизацией по нескольким выходам.
  Без сторонних runtime-зависимостей, кроме `meta`. Опубликован на
  [pub.dev](https://pub.dev/packages/structured_log).

- **[`structured_log_flutter`](structured_log_flutter/)** — headless-ядро
  просмотрщика логов для Flutter-приложений: ограниченный по размеру
  `LogBuffer`, подключаемый напрямую к `structured_log` как синк, и
  фильтрующий `LogViewerController`. Не зависит ни от какой конкретной
  дизайн-системы — фундамент, на котором строится любой UI-скин. *Пока не
  опубликован.*

- **[`structured_log_material`](structured_log_material/)** — готовый к
  использованию in-app просмотрщик логов на Material 3 поверх
  `structured_log_flutter`: живой список, поиск и фильтр по уровню,
  детальный вид развёрнутой записи с копированием, empty-состояния.
  Включает запускаемое пример-приложение (`structured_log_material/example/`,
  умеет в web). *Пока не опубликован.*

- **[`structured_log_fluent`](structured_log_fluent/)** — готовый к
  использованию in-app просмотрщик логов на Fluent UI (WinUI-style) поверх
  `structured_log_flutter`: master-detail split view, поиск и фильтр по
  уровню, панель деталей с копированием, empty-состояния. Включает
  запускаемое пример-приложение (`structured_log_fluent/example/`, умеет в
  web). *Пока не опубликован.*

## Структура репозитория

Каждый пакет — отдельная директория в корне (без вложенности вроде
`packages/`), перечислена по имени в [melos.yaml](melos.yaml) — полный
справочник по инструментам (команды, соглашения, версионирование, CI) для
контрибьюторов в [AGENTS.md](AGENTS.md).

История дизайна и планирования Flutter-пакетов просмотра логов — в
[openspec/changes/add-structured-log-flutter/](openspec/changes/add-structured-log-flutter/)
и
[openspec/changes/add-structured-log-fluent/](openspec/changes/add-structured-log-fluent/)
(почему, технические решения, требования, прогресс по задачам).

## Быстрый старт

```dart
import 'package:structured_log/structured_log.dart';

void main() {
  final log = getLogger();
  log.info('user_login', context: {'user_id': 42, 'ip': '127.0.0.1'});
}
```

Установку и полный справочник API смотрите в README каждого пакета.

## Лицензия

MIT — см. [LICENSE](LICENSE).
