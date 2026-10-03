# structured_log_cherrypick

[![CI](https://github.com/pese-git/structured_log/actions/workflows/ci.yml/badge.svg)](https://github.com/pese-git/structured_log/actions/workflows/ci.yml)

*Read in [English](README.md).*

**Как на самом деле собран граф зависимостей `cherrypick` — скоупы,
модули, циклы и ошибки разрешения структурированными записями лога, без
единого напечатанного экземпляра.**

Документация: [structured-log.openidealab.com](https://structured-log.openidealab.com/ru/).

## Зачем

Ошибки DI-проводки непрозрачны. Незарегистрированная зависимость всплывает
как `StateError` далеко от модуля, который должен был её предоставить, а
неоткрытый скоуп или неустановленный модуль не падают вовсе: приложение
молча получает что-то другое или ничего. Чтобы разобраться, приходится
проходить контейнер отладчиком.

`StructuredLogCherryPickObserver` даёт контейнеру рассказать об этом самому.
Поставленный наблюдателем `cherrypick`, он пишет каждое открытие и закрытие
скоупа, каждую установку модулей, каждый цикл и каждую ошибку разрешения
записью `structured_log` — и проводка, которая состоялась и которая нет,
оказывается в логе рядом со всем остальным, что делало приложение. Сами
экземпляры он не печатает никогда: контейнер держит конфигурацию,
API-клиенты и хранилища токенов.

## Возможности

### Охват

- **Подключение одной строкой** — `CherryPick.setGlobalObserver(StructuredLogCherryPickObserver())`
  или передать наблюдателя одному скоупу.
- **Форма графа** — открытие и закрытие скоупов, установка и удаление
  модулей, освобождение экземпляров.
- **Ошибки проводки** — циклы зависимостей вместе с цепочкой, предупреждения
  контейнера, ошибки разрешения со стеком.
- **Трассировка разрешения по требованию** — регистрации, запросы, создание
  экземпляров, попадания и промахи кэша по умолчанию выключены; любое из
  них можно включить, когда понадобится.

### Управление

- **Тихо по умолчанию, громко когда важно** — скоупы, модули и освобождение
  на `debug`; циклы и ошибки на `error`, предупреждения на `warning`.
- **Свой уровень на каждый хук** — или `null`, чтобы выключить.
- **Своя категория** — каждая запись несёт `category: 'di'`, так что
  `LogSink` может направить её отдельно, а встроенный просмотрщик логов
  предлагает её как фильтр.

### Надёжность

- **Никогда не печатает экземпляр** — только имя и тип, под которыми он
  связан; ошибку — по типу, а не по тексту.
- **Никогда не ломает разрешение** — если логгер бросит исключение,
  пропадёт запись, а не работа контейнера.
- **Работает с `cherrypick` 3.x и 4.x** — чистый Dart, Flutter не нужен.

## Место в проекте

Наблюдателю не нужно ничего, кроме
[`structured_log`](https://pub.dev/packages/structured_log), — ни сервера,
ни Flutter. Его записи уходят в те выводы, которые вы настроили: в консоль,
в файл, во встроенный просмотрщик логов
([`structured_log_material`](https://pub.dev/packages/structured_log_material),
[`structured_log_fluent`](https://pub.dev/packages/structured_log_fluent) или
[`structured_log_cupertino`](https://pub.dev/packages/structured_log_cupertino))
или на self-hosted `structured_log_server` через
[`structured_log_remote_sync`](https://pub.dev/packages/structured_log_remote_sync).
Это один из пяти адаптеров, которые пишут в лог то, что библиотеки
приложения и так делают, и сервер с админ-клиентом этого проекта сами им
пользуются; проект целиком — на
[structured-log.openidealab.com](https://structured-log.openidealab.com/ru/).

## Установка

Опубликован на pub.dev как пре-релиз (`0.1.0-dev.3`):

```yaml
dependencies:
  cherrypick: ">=3.0.0 <5.0.0"
  structured_log: ^0.3.0
  structured_log_cherrypick: ^0.1.0-dev.3
```

## Быстрый старт

```dart
import 'package:cherrypick/cherrypick.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_cherrypick/structured_log_cherrypick.dart';

void main() {
  StructlogConfiguration.configure(
    sinks: [LogSink(name: 'console', output: coloredConsoleOutput)],
  );
  // До первого скоупа: скоуп берёт глобального наблюдателя при создании.
  CherryPick.setGlobalObserver(StructuredLogCherryPickObserver());

  CherryPick.openRootScope().installModules([AppModule()]);
}
```

```text
[2026-10-02T16:04:54.174431Z] DEBUG: di.scope_opened {"logger":"di","category":"di","scope":"scope_1790957094171_5885"}
[2026-10-02T16:04:54.178631Z] DEBUG: di.modules_installed {"logger":"di","category":"di","modules":["AppModule"],"scope":"scope_1790957094171_5885"}
```

Чтобы слушать только один скоуп, передайте наблюдателя ему:
`Scope(null, observer: StructuredLogCherryPickObserver())`.

[example/main.dart](example/main.dart) открывает и закрывает скоуп фичи и
разрешает зависимость, которую никто не зарегистрировал
(`dart run example/main.dart`).

## Что пишется в лог

| Запись                 | Уровень по умолчанию | Поля |
|------------------------|----------------------|------|
| `di.scope_opened`      | `debug`              | `scope` |
| `di.scope_closed`      | `debug`              | `scope` |
| `di.modules_installed` | `debug`              | `modules`, `scope` |
| `di.modules_removed`   | `debug`              | `modules`, `scope` |
| `di.instance_disposed` | `debug`              | `type`, `name`, `scope` |
| `di.cycle_detected`    | `error`              | `chain`, `scope` |
| `di.warning`           | `warning`            | `message` |
| `di.error`             | `error`              | `message`, `error` (тип), `stack_trace` |
| `di.binding_registered`, `di.instance_requested`, `di.instance_created`, `di.cache_hit`, `di.cache_miss` | выключено | `type`, `name`, `scope` |
| `di.diagnostic`        | выключено            | `message` |

Каждая запись несёт ещё `category` (`di`) и `logger` (`di`). `scope` не
пишется, если контейнер его не назвал.

Что сам контейнер сообщает и чего не сообщает — одинаково в 3.0 и 4.0-dev:

- скоуп называется идентификатором, который ему дал контейнер
  (`scope_1790957094171_5885`), а не именем, под которым его открыли;
- `di.scope_closed` приходит только для дочернего скоупа, закрытого через
  родителя (`closeSubScope`), а не для корневого;
- `onInstanceDisposed`, `onCacheHit` и `onCacheMiss` есть в интерфейсе, но
  не вызываются никогда; наблюдатель всё равно их обрабатывает — на случай,
  если начнут;
- о неудачном разрешении контейнер сообщает дважды: один раз без объекта
  ошибки, другой — с ним.

## Как не пустить секреты в лог

Контейнер держит конфигурацию приложения, API-клиенты и хранилища токенов, и
напечатать объект — значит напечатать всё, что он держит. Поэтому:

- **экземпляр не пишется никогда** — ни при создании, ни при освобождении —
  только имя и тип, под которыми он связан;
- **ошибка пишется по типу** (`StateError`), а не по тексту, и со стеком;
- **`details` предупреждения и диагностики отбрасываются**; остаётся только
  сообщение контейнера.

## Настройка

```dart
StructuredLogCherryPickObserver(
  // Трассировать каждое разрешение; null выключает хук.
  levels: const DiLogLevels(
    instanceRequested: LogLevel.trace,
    instanceCreated: LogLevel.trace,
    scopeOpened: null,
  ),
  logger: getLogger('server'),
  category: 'wiring',
);
```

Наблюдатель реализует `CherryPickObserver`, а не наследует
`SilentCherryPickObserver`: контейнер не вызывает наблюдателя, который им
является, и тот бы тоже замолчал.

## Справочник API

| Символ | Описание |
|---|---|
| `StructuredLogCherryPickObserver({logger, loggerName, category, levels})` | Наблюдатель. Без `logger` вызывает `getLogger(loggerName)` (`di`) на каждой записи, поэтому до него доходит и более поздний `StructlogConfiguration.configure`. `category: null` не привязывает категорию. |
| `DiLogLevels({scopeOpened, scopeClosed, modulesInstalled, modulesRemoved, bindingRegistered, instanceRequested, instanceCreated, instanceDisposed, cacheHit, cacheMiss, cycleDetected, diagnostic, warning, error})` | `LogLevel?` на каждый хук; `null` выключает. |

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
- [`structured_log_dio`](https://pub.dev/packages/structured_log_dio) — перехватчик `dio`, логирующий HTTP-вызовы
- [`structured_log_http_client`](https://pub.dev/packages/structured_log_http_client) — обёртка клиента `package:http`, логирующая HTTP-вызовы
- [`structured_log_go_router`](https://pub.dev/packages/structured_log_go_router) — логирует навигацию `go_router`

## Лицензия

MIT — см. [LICENSE](LICENSE).
