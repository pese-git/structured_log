[![CI](https://github.com/pese-git/structured_log/actions/workflows/ci.yml/badge.svg)](https://github.com/pese-git/structured_log/actions/workflows/ci.yml)

*Read in [English](README.md).*

# structured_log Workspace

Monorepo на Melos + FVM для структурированного логирования в Dart,
вдохновлённого Python [`structlog`](https://www.structlog.org/), плюс
экосистема in-app просмотра логов для Flutter поверх него.

## Пакеты

- **[`structured_log`](emb/structured_log/)** — базовая библиотека:
  структурированный JSON-лог с привязкой контекста, типизированными
  correlation-полями, процессорами и маршрутизацией по нескольким выходам.
  Без сторонних runtime-зависимостей, кроме `meta`. Опубликован на
  [pub.dev](https://pub.dev/packages/structured_log).

- **[`structured_log_flutter`](emb/structured_log_flutter/)** — headless-ядро
  просмотрщика логов для Flutter-приложений: ограниченный по размеру
  `LogBuffer`, подключаемый напрямую к `structured_log` как синк, и
  фильтрующий `LogViewerController`. Не зависит ни от какой конкретной
  дизайн-системы — фундамент, на котором строится любой UI-скин. *Пока не
  опубликован.*

- **[`structured_log_material`](emb/structured_log_material/)** — готовый к
  использованию in-app просмотрщик логов на Material 3 поверх
  `structured_log_flutter`: живой список, поиск и фильтр по уровню,
  детальный вид развёрнутой записи с копированием, empty-состояния.
  Включает запускаемое пример-приложение (`emb/structured_log_material/example/`,
  умеет в web). *Пока не опубликован.*

- **[`structured_log_fluent`](emb/structured_log_fluent/)** — готовый к
  использованию in-app просмотрщик логов на Fluent UI (WinUI-style) поверх
  `structured_log_flutter`: master-detail split view, поиск и фильтр по
  уровню, панель деталей с копированием, empty-состояния. Включает
  запускаемое пример-приложение (`emb/structured_log_fluent/example/`, умеет в
  web). *Пока не опубликован.*

- **[`structured_log_cupertino`](emb/structured_log_cupertino/)** — готовый к
  использованию in-app просмотрщик логов на Cupertino (iOS-style) поверх
  `structured_log_flutter`: поиск, фильтры по категории и уровню, на узких
  экранах детали записи открываются отдельным экраном (пушится через
  навигацию), на широких/iPad-размерах — список и master-detail split
  рядом, empty-состояния. Включает запускаемое пример-приложение
  (`emb/structured_log_cupertino/example/`, умеет в web). *Пока не
  опубликован.*

- **[`structured_log_http`](emb/structured_log_http/)** — синк
  `HttpLogOutput`, отправляющий записи лога на сервер `structured_log_server`
  по HTTP, с батчингом и retry/backoff. Единственная зависимость —
  `structured_log`. *Стадия скаффолдинга — реализация в процессе.*

- **[`structured_log_server`](backend/structured_log_server/)** —
  self-hosted мультитенантный сервер приёма, хранения, поиска и живой
  трансляции логов (`shelf`/`shelf_router` + `drift`/SQLite). *Стадия
  скаффолдинга — реализация в процессе.*

## Структура репозитория

Пакеты сгруппированы по категориям верхнего уровня, каждая перечислена по
полному пути в [melos.yaml](melos.yaml): `emb/` — встраиваемые в чужое
приложение библиотеки (`structured_log` и скины просмотрщика логов,
`structured_log_http`), `backend/` — самостоятельные серверные приложения
(`structured_log_server`), `frontend/` — самостоятельные клиентские
приложения с UI (пока пусто — здесь появится `structured_log_admin_client`
по мере реализации), `packages/` — резерв под то, что не подпадает ни под
одну из трёх категорий выше (пока пусто). Полный справочник по инструментам
(команды, соглашения, версионирование, CI) для контрибьюторов — в
[AGENTS.md](AGENTS.md).

История дизайна и планирования Flutter-пакетов просмотра логов — в
[openspec/changes/add-structured-log-flutter/](openspec/changes/add-structured-log-flutter/),
[openspec/changes/add-structured-log-fluent/](openspec/changes/add-structured-log-fluent/)
и
[openspec/changes/add-structured-log-cupertino/](openspec/changes/add-structured-log-cupertino/);
для сервера, его HTTP-sender'а и admin-клиента — в
[openspec/changes/add-structured-log-server/](openspec/changes/add-structured-log-server/)
(почему, технические решения, требования, прогресс по задачам, включая
поэтапный план поставки Этап 0/Этап 1/...).

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
