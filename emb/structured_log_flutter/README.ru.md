# structured_log_flutter

*Read in [English](README.md).*

Headless-ядро просмотрщика логов для [`structured_log`](../structured_log) —
буфер ограниченного размера и фильтрующий контроллер для построения живого
in-app просмотрщика логов во Flutter. Никакой зависимости от Material,
Cupertino или любой другой дизайн-системы: пакет сам ничего не рисует, так что
поверх него можно построить любой UI-скин — на нём построены
[`structured_log_material`](../structured_log_material),
[`structured_log_fluent`](../structured_log_fluent) и
[`structured_log_cupertino`](../structured_log_cupertino).

> **Статус:** опубликован на [pub.dev](https://pub.dev/packages/structured_log_flutter)
> (`0.1.0`). `structured_log_material`, `structured_log_fluent` и
> `structured_log_cupertino` подключают его как обычную hosted-зависимость;
> внутри этого monorepo `melos bootstrap` подставляет вместо неё
> path-зависимость.

## Возможности

- **`LogBuffer`** — кольцевой буфер фиксированной ёмкости, подключается напрямую
  к `structured_log` как `OutputFunction`/`LogSink.output`
- **Живые обновления** — `LogBuffer.entries` — это `ValueListenable`, так что
  виджет может перерисовываться по мере поступления записей без опроса —
  один раз на пачку, а не на каждую запись
- **`LogViewerController`** — `ChangeNotifier` с фильтрацией по уровню/категории/
  тексту поиска, паузой/возобновлением и очисткой поверх `LogBuffer`
- **`debugPrintOutput`** — вывод для консоли телефона: одна простая строка
  на запись через `debugPrint`, без ANSI-цветов
- **`logLevelColor(LogLevel level, Brightness brightness)`** — канонический
  цвет индикатора `LogLevel`, общий для всех скинов, построенных на этом
  пакете, чтобы палитра не расходилась между ними
- **Никаких зависимостей от дизайн-систем** — только `dart:ui`,
  `package:flutter/foundation.dart` и `structured_log`

## Установка

```yaml
dependencies:
  structured_log_flutter: ^0.1.0
```

Требуется `structured_log` версии 0.3.0 или новее.

Внутри этого monorepo `melos bootstrap` подставляет вместо неё
path-зависимость:

```yaml
dependencies:
  structured_log_flutter:
    path: ../structured_log_flutter
```

## Быстрый старт

```dart
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart';

final buffer = LogBuffer(capacity: 500);
final controller = LogViewerController(buffer);

StructlogConfiguration.configure(sinks: [
  LogSink(name: 'console', output: coloredConsoleOutput),
  LogSink(name: 'viewer', output: buffer.capture),
]);

getLogger().info('user_login', context: {'user_id': 42});

controller.levelFilter = LogLevel.warning; // только warning и выше
controller.searchQuery = 'login';          // дополнительно сужено текстом
print(controller.visibleEntries);
```

## Справочник API

### `LogBuffer`

| Член | Описание |
|---|---|
| `LogBuffer({int capacity = 500})` | Создаёт пустой буфер; при превышении `capacity` вытесняется самая старая запись |
| `capture(Map<String, dynamic> entry, LogLevel level)` | Совпадает по сигнатуре с `OutputFunction` — передавайте напрямую как `output` синка |
| `entries` | `ValueListenable<List<Map<String, dynamic>>>`, от старой к новой |
| `clear()` | Опустошает буфер и сразу уведомляет слушателей `entries` |

`entries.value` всегда актуален, но слушателей уведомляют не чаще раза за
оборот цикла событий: пачка записей, залогированных разом, — всё, что
написал один запрос, или плотный цикл, — это одно уведомление и одна
перерисовка, а не по одной на запись. Возвращаемый список неизменяемый и
после чтения уже не меняется, так что ссылку на него можно хранить; два
чтения подряд без новых записей между ними дают один и тот же список —
копия делается раз на прочитанное изменение, а не на каждую запись.

`LogBuffer` держит записи только в памяти. Если логи должны пережить
приложение, нужны файловые выводы — они импортируются из
`package:structured_log/io.dart`.

### `LogViewerController`

`ChangeNotifier`, оборачивающий `LogBuffer`:

| Член | Описание |
|---|---|
| `levelFilter` (`LogLevel?`) | Минимальный уровень видимой записи; `null` — без ограничения |
| `categoryFilter` (`String?`) | Требуемое точное значение `category`; `null` — без ограничения |
| `searchQuery` (`String`) | Регистронезависимое совпадение подстроки с `event` и остальными значениями контекста (`level`/`timestamp` исключены) |
| `paused` (`bool`) | Пока `true`, `visibleEntries` остаются такими, какими были в момент паузы, даже если `buffer` продолжает захватывать записи |
| `visibleEntries` | Записи буфера, отфильтрованные тремя свойствами выше |
| `clear()` | Очищает `buffer` (и зафиксированный снимок, если есть) и уведомляет слушателей |
| `dispose()` | Отписывается от `buffer.entries` — вызывать, когда контроллер больше не нужен |

### `debugPrintOutput`

`OutputFunction`, который пишет каждую запись одной строкой через
`debugPrint`, без ANSI-цветов: местное время (из `timestamp`, с
миллисекундами), уровень, `event` и все остальные поля парами `key=value`:

```text
12:30:15.250 INFO login user="u" attempt=2
```

```dart
StructlogConfiguration.configure(sinks: [
  LogSink(name: 'console', output: debugPrintOutput),
]);
```

Он нужен там, где логи читают в logcat или в консоли Xcode. `defaultOutput`
печатает JSON с отступами на несколько строк, и эти консоли перемешивают их
со всем остальным, а escape-коды `coloredConsoleOutput` в консоли iOS
превращаются в мусор. Значения экранируются так же, как это делает
`formatLogfmt` из `structured_log`, поэтому значение с переводом строки не
разрывает строку лога. `debugPrint` придерживает поток строк, чтобы Android
их не терял, но длинную строку не укорачивает — logcat обрезает строку
длиннее примерно 4 КБ. В терминале на десктопе `coloredConsoleOutput`
по-прежнему читается лучше.

### `logLevelOf(Map<String, dynamic> entry)`

Разбирает ключ контекста `level` записи обратно в `LogLevel` по совпадению
имени — возвращает `null`, если ключа нет или он не распознан. Вынесена в
отдельную функцию, чтобы UI-скин (например, `structured_log_material`) не дублировал
этот разбор.

### `logLevelColor(LogLevel level, Brightness brightness)`

Единственный источник цветов индикатора `LogLevel`: им пользуются строка
списка, вид деталей и бейджи каждого скина. Живёт здесь (а не в
каком-то одном скине), потому что `Color`/`Brightness` не привязаны ни к
Material, ни к Cupertino, ни к Fluent — эта таблица действительно
не зависит от дизайн-системы, в отличие от виджетов, построенных поверх неё.

## Построение UI-скина

`structured_log_flutter` намеренно ничего не рисует — подключайте
`LogViewerController` к любым виджетам, слушая его как обычный `ChangeNotifier`
(`AnimatedBuilder`, `ListenableBuilder` и т.п.) и читая `visibleEntries` для
отображения. Полные эталонные реализации (список, детали записи,
empty-состояния) на Material 3, Fluent UI и Cupertino смотрите в
[`structured_log_material`](../structured_log_material),
[`structured_log_fluent`](../structured_log_fluent) и
[`structured_log_cupertino`](../structured_log_cupertino) соответственно.

## Связанные пакеты

Остальные пакеты семейства `structured_log`:

**Ядро**

- [`structured_log`](https://pub.dev/packages/structured_log) — структурированное JSON-логирование с привязкой контекста, процессорами и маршрутизацией по синкам

**Просмотрщик логов в приложении**

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

MIT
