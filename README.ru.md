[![CI](https://github.com/pese-git/structured_log/actions/workflows/ci.yml/badge.svg)](https://github.com/pese-git/structured_log/actions/workflows/ci.yml)

*Read in [English](README.md).*

# structured_log Workspace

Monorepo на Melos + FVM для структурированного логирования в Dart,
вдохновлённого Python [`structlog`](https://www.structlog.org/): само ядро,
экосистема in-app просмотра логов для Flutter поверх него и self-hosted
сервер, чтобы отправлять логи с устройства и читать их обратно.

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
  по HTTP: батчинг по размеру или таймауту, retry с backoff, ограниченный
  буфер и `flushed`, чтобы дождаться доставки перед выходом. Никогда не
  блокирует того, кто логировал. Единственная зависимость —
  `structured_log`. *Пока не опубликован.*

- **[`structured_log_server`](backend/structured_log_server/)** —
  self-hosted мультитенантный сервер приёма, хранения, поиска и живой
  трансляции логов (`shelf`/`shelf_router` + `drift`/SQLite). Работают приём
  и запрос логов, живой поток (SSE), группы/проекты/секретные ключи,
  аутентификация, RBAC, квоты, очистка по retention и ограничение частоты;
  управление пользователями, команды, выдача ролей, аудит и email-флоу
  специфицированы, но не реализованы. Не публикуется — это сервис, который
  запускают, а не библиотека, от которой зависят.

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

**Впервые здесь?** Начните с [docs/guides/](docs/guides/README.ru.md) —
руководства пользователя, администратора/DevOps и разработчика, каждое
отвечает на «как это реально сделать» для своей аудитории. В
[docs/](docs/) также лежит сквозная (не per-package) документация
*дизайна* серверной системы — HTTP API и JSON-модели, аутентификация и
RBAC, хранилище, живая трансляция, квоты и эксплуатационная
конфигурация — билингвальными парами; полное оглавление в
[docs/README.md](docs/README.md).

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

Логирование — одним лишь ядром:

```dart
import 'package:structured_log/structured_log.dart';

void main() {
  final log = getLogger();
  log.info('user_login', context: {'user_id': 42, 'ip': '127.0.0.1'});
}
```

Отправка этих записей на сервер — вместо консоли или вместе с ней:

```dart
final output = HttpLogOutput(
  serverUrl: 'https://logs.example.com',
  projectSecretKey: 'slk_...',
);
StructlogConfiguration.configure(
  sinks: [LogSink(name: 'server', output: output)],
);
```

Запуск самого сервера — путь от пустой БД до прочитанного лога описан в
[backend/structured_log_server/README.ru.md](backend/structured_log_server/README.ru.md):

```bash
export STRUCTURED_LOG_JWT_SECRET='длинная-случайная-строка'
dart run bin/server.dart serve --db-path=./logs.sqlite
```

Установку и полный справочник API смотрите в README каждого пакета.

## Лицензия

MIT — см. [LICENSE](LICENSE).
