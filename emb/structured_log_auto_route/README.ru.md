# structured_log_auto_route

[![CI](https://github.com/pese-git/structured_log/actions/workflows/ci.yml/badge.svg)](https://github.com/pese-git/structured_log/actions/workflows/ci.yml)

*Read in [English](README.md).*

**Каждый экран, который приложение на `auto_route` открыло, закрыло или на
который переключилось, попадает в лог структурированной записью. Токены в
расположении скрыты, а настройка занимает одну строку.**

Документация: [structured-log.openidealab.com](https://structured-log.openidealab.com/ru/).

## Зачем

«Как пользователь сюда попал?» — первый вопрос к любой ошибке на экране, и
ответ — путь, которым он шёл. Без записей остаётся воспроизводить ошибку
руками или писать `NavigatorObserver` с `print`, а на устройстве пользователя
нельзя ни то, ни другое.

`StructuredLogAutoRouteObserver` ведёт эти записи за вас. Его передают роутеру
один раз, и он пишет каждый открытый, закрытый или убранный экран и каждое
переключение вкладки записями `structured_log`. Имя маршрута, его шаблон и
расположение лежат в отдельных полях, так что историю одного экрана легко
выделить среди остальных записей. Эти же записи показывает встроенный
просмотрщик логов и хранит `structured_log_server`.

## Возможности

### Охват

- **Подключение одной строкой** —
  `appRouter.config(navigatorObservers: () => [StructuredLogAutoRouteObserver()])`.
- **Открытие, закрытие, удаление, вкладки** — то, что `auto_route` сообщает
  `NavigatorObserver`, плюс хуки вкладок `AutoRouterObserver`.
- **Экраны различимы** — по имени (`UserRoute`), по шаблону (`/user/:id`) и по
  тому, где они на самом деле (`/user/7?tab=posts`).
- **Вложенные маршруты** — экран внутри оболочки расположен под своими
  родителями.
- **Работает и со сгенерированным, и с рукописным роутером** — зависит только
  от `package:auto_route`.

### Управление

- **Своя категория** — у каждой записи `category: 'navigation'`, так что
  `LogSink` может направлять навигацию отдельно, а встроенный просмотрщик
  логов предлагает её как фильтр. Та же категория у `structured_log_go_router`.
- **Свой уровень на каждое событие** — или `null`, чтобы событие выключить.
- **Фильтр** — шумные экраны можно вовсе не пускать в лог.

### Надёжность

- **Токены в лог не попадают** — значения `token`, `code`, `password` и
  остальных имён из настраиваемого списка заменяются на `REDACTED` в
  параметрах пути, в query и во фрагменте вида OAuth.
- **Никогда не ломает навигацию** — если фильтр или логгер выбросят
  исключение, записи не будет, а навигация пройдёт.
- **Выключенное не тратит ресурсов** — для выключенного события,
  отфильтрованного экрана или уровня, который не принимает ни один вывод,
  запись не строится.

## Место в проекте

Наблюдателю не нужно ничего, кроме
[`structured_log`](https://pub.dev/packages/structured_log), — сервер не
нужен. Его записи уходят в те выводы, которые вы настроили: в консоль, в
файл, во встроенный просмотрщик логов
([`structured_log_material`](https://pub.dev/packages/structured_log_material),
[`structured_log_fluent`](https://pub.dev/packages/structured_log_fluent) или
[`structured_log_cupertino`](https://pub.dev/packages/structured_log_cupertino)),
где категория `navigation` становится фильтром, или на self-hosted
`structured_log_server` через
[`structured_log_remote_sync`](https://pub.dev/packages/structured_log_remote_sync).
Это один из девяти адаптеров, которые пишут в лог то, что библиотеки
приложения и так делают; проект целиком — на
[structured-log.openidealab.com](https://structured-log.openidealab.com/ru/).

## Установка

Работает с `auto_route` 10 и 11. Для `go_router` нужен
[`structured_log_go_router`](https://pub.dev/packages/structured_log_go_router).

Опубликован на pub.dev как пре-релиз:

```yaml
dependencies:
  auto_route: ">=10.0.0 <12.0.0"
  structured_log: ^0.3.0
  structured_log_auto_route: ^0.1.0-dev.1
```

## Быстрый старт

```dart
import 'package:flutter/material.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_auto_route/structured_log_auto_route.dart';

void main() {
  StructlogConfiguration.configure(
    sinks: [LogSink(name: 'console', output: coloredConsoleOutput)],
  );

  final appRouter = AppRouter();
  runApp(
    MaterialApp.router(
      routerConfig: appRouter.config(
        navigatorObservers: () => [StructuredLogAutoRouteObserver()],
      ),
    ),
  );
}
```

`navigatorObservers` — это построитель: `auto_route` спрашивает у него
наблюдателей для каждого создаваемого навигатора, вложенные включая, так что
можно возвращать **нового** наблюдателя или один и тот же — состояния он не
держит.

Экран пользователя с токеном в query, замена его настройками и возврат пишут:

```text
[2026-10-19T07:11:40.802293Z] INFO: route_pushed {"logger":"router","category":"navigation","route":"User","route_path":"/user/:id","location":"/user/42?token=REDACTED&tab=posts","previous_route":"Home","previous_location":"/"}
[2026-10-19T07:11:40.904616Z] INFO: route_pushed {"logger":"router","category":"navigation","route":"Settings","route_path":"/settings","location":"/settings","previous_route":"User","previous_location":"/user/42"}
[2026-10-19T07:11:40.905216Z] INFO: route_removed {"logger":"router","category":"navigation","route":"User","route_path":"/user/:id","location":"/user/42?token=REDACTED&tab=posts","previous_route":"Home","previous_location":"/"}
```

Запускаемая версия — [example/main.dart](example/main.dart).

## Что пишется в лог

У каждой записи есть `category` (по умолчанию `navigation`), `logger` (по
умолчанию `router`) и поля экрана, о котором она:

- `route` — имя маршрута, например `User`;
- `route_path` — его шаблон пути, например `/user/:id`;
- `location` — где он на самом деле, например `/user/42?tab=posts`, с
  замаскированными чувствительными значениями. Вложенные маршруты расположены
  под своими родителями.

| Событие | Когда | Уровень по умолчанию | Ещё несёт |
|---|---|---|---|
| `route_pushed` | экран открыт | `info` | `previous_route`, `previous_location` |
| `route_popped` | экран закрыт | `info` | экран, который показан снова, как `previous_*` |
| `route_removed` | экран убран из стека без `pop` | `info` | `previous_*` |
| `route_replaced` | навигатор сам сообщил о замене | `info` | прежний экран, как `previous_*` |
| `route_tab_changed` | вкладка `TabsRouter` активирована или выбрана | `info` | `tab_index`, `tab_event` (`init` или `change`), `previous_route` |

`previous_location` — **только путь**, без query и фрагмента. `auto_route`
держит query текущей навигации на роутере, а не на каждом маршруте, поэтому
собственный query соседа не отличить от query того, что движется.

`replace` — это не `route_replaced`: стек страничный, и навигатор сообщает об
открытии нового экрана и об удалении старого. Вы увидите `route_pushed`, а за
ним `route_removed`. `route_replaced` оставлен для версии, которая сообщит о
замене сама.

Запись о вкладке называет её собственным путём (`/feed`), а не под оболочкой:
хуки вкладок оболочку не несут. Придёт ли первый заход на вторую вкладку как
`init` или как `change`, решает `auto_route`, и между версиями 10 и 11 это
разное.

Экран, открытый мимо роутера (диалог, bottom sheet), пишется под именем из его
настроек или своим типом, без `route_path` и `location`. Фильтр его не видит.

### Что не пишется

Наблюдатель видит то, что видит `Navigator`. До него не доходят три вещи:

- **Маршрут, обновлённый на месте.** `navigatePath('/user/9')` при открытом
  `/user/7` оставляет тот же экран и меняет его параметры; навигатор об этом
  не узнаёт, записи нет.
- **Путь, который не подошёл ни одному маршруту.** `auto_route` сообщает о нём
  в `onFailure` одного этого вызова, глобально — нигде.
- **Решения защитников.** `AutoRouteGuard` работает раньше, чем навигатор
  вступает в дело.

## Как не пустить секреты в лог

Значения этих имён заменяются на `REDACTED` без учёта регистра, где бы они ни
встретились — в параметре пути, в параметре query, во фрагменте вида запроса
(`#access_token=...`):

`access_token`, `refresh_token`, `id_token`, `token`, `api_key`, `apikey`,
`password`, `client_secret`, `code`.

Шаблон в `route_path` значений не несёт и пишется как есть. Список заменяется
через `redactedParameters`:

```dart
StructuredLogAutoRouteObserver(
  redactedParameters: {...defaultRedactedParameters, 'session'},
)
```

Имена пишутся строчными. Больше о маршруте не пишется ничего: `extra`, `args`
и виджеты страницы не читаются.

## Настройка

```dart
StructuredLogAutoRouteObserver(
  // Какие события писать и с каким уровнем; null выключает.
  levels: const RouteLogLevels(
    pushed: LogLevel.debug,
    popped: null,
  ),
  // Экраны — мимо лога. Отвергнутый маршрут не пишется и не появляется
  // как сосед других.
  filter: (route) => route.name != 'Splash',
  category: 'screens',
)
```

## Справочник API

| Символ | Описание |
|---|---|
| `StructuredLogAutoRouteObserver({logger, loggerName, category, levels, redactedParameters, filter})` | Наблюдатель, наследник `AutoRouterObserver`. Без `logger` вызывает `getLogger(loggerName)` на каждой записи, поэтому до него доходит и более поздний `StructlogConfiguration.configure`. `category: null` не привязывает категорию. |
| `RouteLogLevels({pushed, popped, removed, replaced, tabChanged})` | `LogLevel?` на каждое событие; `null` выключает событие. |
| `defaultRedactedParameters` | Набор имён по умолчанию, значения которых скрываются. |
| `redactedValue` | `'REDACTED'`. |

## Связанные пакеты

Остальные пакеты семейства `structured_log`:

**Ядро**

- [`structured_log`](https://pub.dev/packages/structured_log) — структурированное JSON-логирование с привязкой контекста, процессорами и маршрутизацией по синкам

**Просмотрщик логов в приложении**

- [`structured_log_flutter`](https://pub.dev/packages/structured_log_flutter) — headless-ядро просмотрщика: `LogBuffer` и `LogViewerController`
- [`structured_log_material`](https://pub.dev/packages/structured_log_material) — просмотрщик на Material 3
- [`structured_log_fluent`](https://pub.dev/packages/structured_log_fluent) — просмотрщик на Fluent UI (в стиле WinUI)
- [`structured_log_cupertino`](https://pub.dev/packages/structured_log_cupertino) — просмотрщик на Cupertino (в стиле iOS)

**Доставка логов на сервер**

- [`structured_log_remote_sync`](https://pub.dev/packages/structured_log_remote_sync) — синк с батчингом и повторами для self-hosted `structured_log_server`

**Интеграции**

- [`structured_log_bloc`](https://pub.dev/packages/structured_log_bloc) — `BlocObserver` для `bloc`/`flutter_bloc`
- [`structured_log_riverpod`](https://pub.dev/packages/structured_log_riverpod) — `ProviderObserver` для `riverpod`/`flutter_riverpod`
- [`structured_log_dio`](https://pub.dev/packages/structured_log_dio) — перехватчик `dio`, логирующий HTTP-вызовы
- [`structured_log_http_client`](https://pub.dev/packages/structured_log_http_client) — обёртка клиента `package:http`, логирующая HTTP-вызовы
- [`structured_log_go_router`](https://pub.dev/packages/structured_log_go_router) — логирует навигацию `go_router`
- [`structured_log_cherrypick`](https://pub.dev/packages/structured_log_cherrypick) — наблюдатель DI-контейнера `cherrypick`
- [`structured_log_drift`](https://pub.dev/packages/structured_log_drift) — `QueryInterceptor` для drift, логирующий запросы, сбои и транзакции
- [`structured_log_logging`](https://pub.dev/packages/structured_log_logging) — мост, передающий записи `package:logging` в `structured_log`

## Лицензия

MIT — см. [LICENSE](LICENSE).
