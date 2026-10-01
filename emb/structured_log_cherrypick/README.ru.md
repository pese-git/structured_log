# structured_log_cherrypick

[![CI](https://github.com/pese-git/structured_log/actions/workflows/ci.yml/badge.svg)](https://github.com/pese-git/structured_log/actions/workflows/ci.yml)

*Read in [English](README.md).*

Пишет в лог, что делает DI-контейнер
[`cherrypick`](https://pub.dev/packages/cherrypick), — открытие и закрытие
скоупов, установку модулей, циклы зависимостей, ошибки разрешения —
записями [`structured_log`](https://pub.dev/packages/structured_log).

`StructuredLogCherryPickObserver` — обычный `CherryPickObserver`: достаточно
поставить его глобальным наблюдателем контейнера, и контейнер пишет в уже
настроенные выводы — консоль, файл, встроенный просмотрщик логов
(`structured_log_flutter`) или `structured_log_server` через
`structured_log_http`. Так становится видна проводка, которая молча не
состоялась: скоуп, который не открылся, модуль, который не установился.

## Возможности

- **Подключение одной строкой** — `CherryPick.setGlobalObserver(StructuredLogCherryPickObserver())`
- **Тихо по умолчанию, громко когда важно** — скоупы, модули и освобождение
  на `debug`; циклы и ошибки на `error`, предупреждения на `warning`;
  болтовня на каждом разрешении выключена
- **Никогда не печатает экземпляр** — только имя и тип, под которыми он
  связан; ошибку — по типу, а не по тексту
- **Своя категория** — каждая запись несёт `category: 'di'`
- **Свой уровень на каждый хук** — или `null`, чтобы выключить; трассировку
  разрешения можно включить, когда она нужна
- **Никогда не ломает разрешение** — бросивший логгер стоит записи, а не
  работы контейнера
- **Работает с `cherrypick` 3.x и 4.x** — чистый Dart, Flutter не нужен

## Установка

На pub.dev пока не опубликован (`0.1.0-dev.0`) — подключайте как path- или
git-зависимость:

```yaml
dependencies:
  cherrypick: ">=3.0.0 <5.0.0"
  structured_log: ^0.2.1
  structured_log_cherrypick:
    path: ../structured_log_cherrypick # внутри этого монорепозитория
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
DEBUG: di.scope_opened      {"category":"di","scope":"scope_1790868703933_1"}
DEBUG: di.modules_installed {"category":"di","modules":["AppModule"],"scope":"scope_1790868703933_1"}
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
  (`scope_1790868703933_1`), а не именем, под которым его открыли;
- `di.scope_closed` приходит только для дочернего скоупа, закрытого через
  родителя (`closeSubScope`), а не для корневого;
- `onInstanceDisposed`, `onCacheHit` и `onCacheMiss` есть в интерфейсе, но
  не вызываются никогда; наблюдатель обрабатывает их на тот день, когда
  начнут;
- неудачное разрешение сообщается дважды: один раз без объекта ошибки,
  один раз с ним.

## Как не пустить секреты в лог

Контейнер держит конфигурацию приложения, API-клиенты и хранилища токенов, и
напечатанный объект — это напечатанное всё, что он держит. Поэтому:

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

## Лицензия

См. [LICENSE](LICENSE).
