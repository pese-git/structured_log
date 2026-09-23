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
  дизайн-системы — фундамент, на котором строится любой UI-скин.
  Опубликован на
  [pub.dev](https://pub.dev/packages/structured_log_flutter).

- **[`structured_log_material`](emb/structured_log_material/)** — готовый к
  использованию in-app просмотрщик логов на Material 3 поверх
  `structured_log_flutter`: живой список, поиск и фильтр по уровню,
  детальный вид развёрнутой записи с копированием, empty-состояния.
  Включает запускаемое пример-приложение (`emb/structured_log_material/example/`,
  умеет в web). Опубликован на
  [pub.dev](https://pub.dev/packages/structured_log_material).

- **[`structured_log_fluent`](emb/structured_log_fluent/)** — готовый к
  использованию in-app просмотрщик логов на Fluent UI (WinUI-style) поверх
  `structured_log_flutter`: master-detail split view, поиск и фильтр по
  уровню, панель деталей с копированием, empty-состояния. Включает
  запускаемое пример-приложение (`emb/structured_log_fluent/example/`, умеет в
  web). Опубликован на
  [pub.dev](https://pub.dev/packages/structured_log_fluent).

- **[`structured_log_cupertino`](emb/structured_log_cupertino/)** — готовый к
  использованию in-app просмотрщик логов на Cupertino (iOS-style) поверх
  `structured_log_flutter`: поиск, фильтры по категории и уровню, на узких
  экранах детали записи открываются отдельным экраном (пушится через
  навигацию), на широких/iPad-размерах — список и master-detail split
  рядом, empty-состояния. Включает запускаемое пример-приложение
  (`emb/structured_log_cupertino/example/`, умеет в web). Опубликован на
  [pub.dev](https://pub.dev/packages/structured_log_cupertino).

- **[`structured_log_http`](emb/structured_log_http/)** — синк
  `HttpLogOutput`, отправляющий записи лога на сервер `structured_log_server`
  по HTTP: батчинг по размеру или таймауту, retry с backoff, ограниченный
  буфер и `flushed`, чтобы дождаться доставки перед выходом. Никогда не
  блокирует вызывающий код. Единственная зависимость —
  `structured_log`. *Пока не опубликован.*

- **[`structured_log_server`](backend/structured_log_server/)** —
  self-hosted мультитенантный сервер приёма, хранения, поиска и живой
  трансляции логов (`shelf`/`shelf_router` + `drift`, SQLite по умолчанию
  либо PostgreSQL как выбираемая оператором альтернатива). Работают приём
  и запрос логов, живой поток (SSE), группы/проекты/секретные
  ключи/команды, аутентификация, RBAC, квоты, очистка по retention,
  ограничение частоты, управление пользователями и журнал аудита;
  самостоятельная регистрация, восстановление пароля и подтверждение
  email специфицированы, но не реализованы. Не публикуется — это сервис,
  который запускают, а не библиотека, от которой зависят.

- **[`structured_log_admin_ui`](frontend/structured_log_admin_ui/)** —
  библиотека UI-компонентов, из которых собран admin-клиент (Atomic
  Design: tokens/atoms/molecules/organisms, на базе Fluent UI). Зависит
  только от `flutter` и `fluent_ui` — ничего не знает о слое данных или
  навигации клиента. Включает запускаемую галерею компонентов
  (`frontend/structured_log_admin_ui/example/`, умеет в web). Не
  публикуется — заточена под эстетику этого конкретного клиента, а не
  кит общего назначения.

- **[`structured_log_admin_client`](frontend/structured_log_admin_client/)**
  — веб-приложение, которым реально пользуются операторы и их команды:
  вход и принудительная смена пароля, ролевой admin-дашборд,
  группы/проекты/команды/секретные ключи, поиск логов с живой лентой,
  управление пользователями и журнал аудита. Локализовано
  (английский/русский). Не публикуется — самостоятельное приложение, а
  не библиотека.

- **[`structured_log_e2e`](packages/e2e/)** — сквозные тесты, которые
  поднимают настоящий сервер отдельным процессом и гоняют через него всю
  цепочку: `structured_log`/`HttpLogOutput` на входе,
  репозитории/`ApiClient` admin-клиента на выходе — покрывают швы, до
  которых не достают ни юнит-, ни интеграционные тесты по отдельности.
  Не публикуется — тестовый харнесс, а не библиотека.

## Структура репозитория

Пакеты сгруппированы по категориям верхнего уровня, каждая перечислена по
полному пути в [melos.yaml](melos.yaml): `emb/` — встраиваемые в чужое
приложение библиотеки (`structured_log` и скины просмотрщика логов,
`structured_log_http`), `backend/` — самостоятельные серверные приложения
(`structured_log_server`), `frontend/` — самостоятельные клиентские
приложения с UI (`structured_log_admin_ui`, `structured_log_admin_client`),
`packages/` — то, что не подпадает ни под одну из трёх категорий выше
(`structured_log_e2e`, сквозные тесты по всей системе). Полный справочник
по инструментам (команды, соглашения, версионирование, CI) для
контрибьюторов — в [AGENTS.md](AGENTS.md).

**Впервые здесь?** Начните с [docs/guides/](docs/guides/README.ru.md) —
руководства пользователя, администратора/DevOps, разработчика и
контрибьютора, каждое отвечает на «как это реально сделать» для своей
аудитории. В
[docs/](docs/) также лежит сквозная (не per-package) документация
*дизайна* серверной системы — HTTP API и JSON-модели, аутентификация и
RBAC, хранилище, живая трансляция, квоты и эксплуатационная
конфигурация — билингвальными парами; полное оглавление в
[docs/README.md](docs/README.md).

**[`site/`](site/)** публикует то же самое содержимое [docs/](docs/) как
удобный для просмотра и поиска сайт (английский/русский) — проект на
[Astro](https://astro.build)+[Starlight](https://starlight.astro.build),
вне Dart/Flutter Melos workspace. Он сгенерирован из `docs/` скриптом, а
не написан вручную; см. [site/README.md](site/README.md). Запуск локально:

```bash
cd site && npm install && npm run dev
```

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
