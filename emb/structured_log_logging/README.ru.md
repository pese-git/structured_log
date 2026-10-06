# structured_log_logging

[![CI](https://github.com/pese-git/structured_log/actions/workflows/ci.yml/badge.svg)](https://github.com/pese-git/structured_log/actions/workflows/ci.yml)

*Read in [English](README.md).*

**Логи всех библиотек, которые пишут через `package:logging`, попадают в
`structured_log` — в те же выводы, встроенный просмотрщик и на тот же
сервер, что и ваши собственные записи. Хватает одной строки настройки.**

Документация: [structured-log.openidealab.com](https://structured-log.openidealab.com/ru/).

## Зачем

Через `package:logging` логирует большая часть экосистемы Dart: драйверы баз
данных, генераторы кода, HTTP-стеки, множество прикладных библиотек. Сами по
себе их записи никуда не попадают — только тому, кто подписан на
`Logger.root.onRecord`, а это обычно `print` в `main`. До файла с логом,
встроенного просмотрщика или self-hosted `structured_log_server` они не
доходят, и в журнале, который открывают после инцидента, не оказывается
записей как раз того драйвера, который упал.

`StructuredLogLoggingBridge` закрывает этот разрыв. Его подключают один раз,
и каждая запись `package:logging` становится записью `structured_log`: её
маршрутизируют, фильтруют, маскируют и отправляют на сервер как любую другую,
а библиотеки, которые её написали, трогать не нужно.

## Возможности

### Охват

- **Подключение одной строкой** — `StructuredLogLoggingBridge().attach()`.
- **Все библиотеки сразу** — мост слушает `Logger.root`, единственный поток,
  через который проходит каждая запись `package:logging`.
- **Записи в той же форме, что ваши** — ошибка и стек становятся полями
  `error`, `error_type` и `stack_trace`, ровно как у `BoundLogger.error`.
- **Уровни по значению** — `FINE` становится `debug`, `SEVERE` — `error`, а
  собственный `Level('NOTICE', 850)` попадает в `info` без всякой настройки.

### Управление

- **Своя категория** — каждая запись несёт `category: 'logging'`, так что
  `LogSink` может взять или отбросить всё, что написали другие библиотеки.
- **Своё сопоставление уровней** — его можно заменить, а `null` отбрасывает
  уровень целиком.
- **Фильтр** — шумные логгеры можно не пускать в лог вовсе.
- **Свои поля** — например, id запроса из зоны записи или что угодно ещё,
  что запись несёт.

### Безопасность

- **Никогда не бросает в вызывающий код** — мост выполняется внутри вызова
  `Logger.log` самой библиотеки, и её вызов завершается как обычно. Если
  исключение выбросит фильтр или сопоставление уровней, запись не пишется:
  ими отсекают записи, и мост ошибается в эту сторону. Если выбросит функция
  контекста, запись пишется без её полей, а поле `bridge_failed` называет
  тип исключения.
- **Не трогает `package:logging`** — мост никогда не меняет уровень логгеров
  и `hierarchicalLoggingEnabled`.

## Место в проекте

Мосту не нужно ничего, кроме
[`structured_log`](https://pub.dev/packages/structured_log) и
`package:logging`, — ни сервера, ни Flutter, и он работает в web. Его записи
уходят в те выводы, которые вы настроили: в консоль, в файл, во встроенный
просмотрщик логов
([`structured_log_material`](https://pub.dev/packages/structured_log_material),
[`structured_log_fluent`](https://pub.dev/packages/structured_log_fluent) или
[`structured_log_cupertino`](https://pub.dev/packages/structured_log_cupertino)),
где категория `logging` становится фильтром, или на self-hosted
`structured_log_server` через
[`structured_log_remote_sync`](https://pub.dev/packages/structured_log_remote_sync).
Это один из шести адаптеров, которые пишут в лог то, что библиотеки
приложения и так делают; проект целиком — на
[structured-log.openidealab.com](https://structured-log.openidealab.com/ru/).

## Установка

Пакет ещё не опубликован на pub.dev (`0.1.0-dev.0`), поэтому пока
подключайте его по пути или из git:

```yaml
dependencies:
  logging: ^1.2.0
  structured_log: ^0.3.0
  structured_log_logging:
    path: ../structured_log_logging # внутри этого монорепозитория
```

## Быстрый старт

```dart
import 'package:logging/logging.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_logging/structured_log_logging.dart';

void main() {
  StructlogConfiguration.configure(
    sinks: [LogSink(name: 'console', output: coloredConsoleOutput)],
  );
  Logger.root.level = Level.ALL; // см. «Какие записи доходят» ниже
  StructuredLogLoggingBridge().attach();

  // ...
}
```

Драйвер базы данных, пишущий через `package:logging`, после этого даёт:

```text
[2026-10-05T09:39:05.575330Z] INFO: connection opened {"logger":"db","category":"logging"}
[2026-10-05T09:39:05.578816Z] DEBUG: query took 3 ms {"logger":"db","category":"logging"}
[2026-10-05T09:39:05.579002Z] ERROR: query failed {"logger":"db","category":"logging","error":"Bad state: connection closed","error_type":"StateError"}
```

Запускаемая версия — в [example/main.dart](example/main.dart)
(`dart run example/main.dart`).

## Что пишется в лог

Каждая `LogRecord` даёт одну запись:

| Запись `package:logging` | Запись `structured_log` |
|---|---|
| `message` | `event` |
| `loggerName` | `logger` (`root` для корневого логгера) |
| `level` | `level`, по таблице ниже |
| `error` | `error` (его `toString()`) и `error_type` |
| `stackTrace` | `stack_trace` |
| — | `category: 'logging'` |

Поле `object` записи не пишется: его `toString()` уже и есть сообщение. Не
пишутся и `time`, `sequenceNumber`, `zone`: `structured_log` ставит свой
`timestamp`, а всё остальное можно добавить через `context`.

| `Level.value` | Уровень | Стандартные уровни |
|---|---|---|
| меньше 500 | `trace` | `FINEST`, `FINER` |
| 500–699 | `debug` | `FINE` |
| 700–899 | `info` | `CONFIG`, `INFO` |
| 900–999 | `warning` | `WARNING` |
| 1000–1199 | `error` | `SEVERE` |
| 1200 и выше | `critical` | `SHOUT` |

При заданном `recordStackTraceAtLevel` `package:logging` сам добавляет стек,
а если ошибки нет — ставит на её место строку `autogenerated stack trace
for …`. Мост стек оставляет, а эту строку не пишет.

## Какие записи доходят

Мост видит только те записи, которые `package:logging` создаёт, а
`Logger.root` по умолчанию создаёт записи уровня `INFO` и выше: вызов
`fine(...)` ниже этого порога отбрасывается раньше, чем о нём узнает
какой-либо слушатель. Мост этот порог за вас не меняет: если опустить
`Logger.root.level`, каждая библиотека приложения начнёт собирать сообщения,
которые раньше пропускала, и решать это вам, а не мосту.

```dart
Logger.root.level = Level.ALL;
```

Дальше, как и для любой записи, решает `minLevel` самого вывода.

## Как не пустить секреты в лог

Библиотеки пишут в сообщение что угодно: URL вместе с query, SQL-запрос с
аргументами, заголовок. Сообщение становится полем `event` — обычной
строкой, и `redactKeys` внутрь неё не заглядывает. То, чему не доверяете,
лучше не пускать:

```dart
StructuredLogLoggingBridge(
  // Слишком болтливый или слишком откровенный логгер.
  filter: (record) => record.loggerName != 'http.wire',
  // Уровень, который не нужен ни от кого.
  levelOf: (level) => level < Level.FINE ? null : defaultLogLevelOf(level),
).attach();
```

А для того, что осталось, — свой процессор, переписывающий `event` у
записей с `category: 'logging'`.

## Логирование из вывода

`package:logging` публикует каждую запись синхронно, и его поток не начинает
рассылать новую запись, пока не закончил с текущей. Мост доставляет запись
*во время* этой рассылки. Поэтому код, который выполняет вывод или процессор
`structured_log` и который сам пишет через `package:logging` (например,
вывод поверх клиента, логирующего через него), получит от этого вызова
`StateError`. Зациклиться мост из-за этого не может, но исключение увидит
библиотека, сделавшая вызов. Из вывода пишите асинхронно или не через
`package:logging`.

## Настройка

```dart
StructuredLogLoggingBridge(
  // Другой логгер вместо Logger.root; имеет смысл только при
  // hierarchicalLoggingEnabled, когда у каждого логгера свой поток.
  source: Logger('app'),
  // Своё сопоставление уровней; null отбрасывает уровень.
  levelOf: defaultLogLevelOf,
  // Какие записи не пускать.
  filter: (record) => !record.loggerName.startsWith('build'),
  // null — без категории.
  category: 'libraries',
  // Дополнительные поля, например id запроса из зоны записи.
  context: (record) => {'request_id': record.zone?[#requestId]},
).attach();
```

Повторный `attach` на подключённом мосте ничего не делает; `detach`
останавливает мост, а `attach` подключает его снова.

## Справочник API

| Символ | Описание |
|---|---|
| `StructuredLogLoggingBridge({source, levelOf, filter, category, context})` | Мост. Для каждой записи вызывает `getLogger(loggerName)`, поэтому более поздний `StructlogConfiguration.configure` до него тоже доходит. `category: null` — без категории. |
| `attach()` / `detach()` / `isAttached` | Начать передавать записи `source`, остановиться или узнать, что сейчас. |
| `LogLevelOf` | `LogLevel? Function(Level level)` — уровень, с которым пишется запись; `null` её отбрасывает. |
| `defaultLogLevelOf(level)` | Сопоставление по умолчанию, по `Level.value`. |

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
- [`structured_log_cherrypick`](https://pub.dev/packages/structured_log_cherrypick) — наблюдатель DI-контейнера `cherrypick`

## Лицензия

MIT — см. [LICENSE](LICENSE).
