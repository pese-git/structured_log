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
- **Живые обновления** — `LogBuffer.entries` это `ValueListenable`, виджет может
  перерисовываться на каждую новую запись без опроса
- **`LogViewerController`** — `ChangeNotifier` с фильтрацией по уровню/категории/
  тексту поиска, паузой/возобновлением и очисткой поверх `LogBuffer`
- **`logLevelColor(LogLevel level, Brightness brightness)`** — канонический
  цвет индикатора `LogLevel`, общий для всех скинов, построенных на этом
  пакете, чтобы палитра не расходилась между ними
- **Ноль зависимостей от дизайн-системы** — только `dart:ui`,
  `package:flutter/foundation.dart` и `structured_log`

## Установка

```yaml
dependencies:
  structured_log_flutter: ^0.1.0
```

Внутри этого monorepo `melos bootstrap` подставляет вместо этого
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
| `clear()` | Опустошает буфер и уведомляет слушателей `entries` |

### `LogViewerController`

`ChangeNotifier`, оборачивающий `LogBuffer`:

| Член | Описание |
|---|---|
| `levelFilter` (`LogLevel?`) | Минимальный уровень видимой записи; `null` — без ограничения |
| `categoryFilter` (`String?`) | Требуемое точное значение `category`; `null` — без ограничения |
| `searchQuery` (`String`) | Регистронезависимое совпадение подстроки с `event` и остальными значениями контекста (`level`/`timestamp` исключены) |
| `paused` (`bool`) | Пока `true`, `visibleEntries` зафиксированы на состоянии на момент паузы, даже если `buffer` продолжает захватывать записи |
| `visibleEntries` | Записи буфера, отфильтрованные тремя свойствами выше |
| `clear()` | Очищает `buffer` (и зафиксированный снимок, если есть) и уведомляет слушателей |
| `dispose()` | Отписывается от `buffer.entries` — вызывать, когда контроллер больше не нужен |

### `logLevelOf(Map<String, dynamic> entry)`

Разбирает ключ контекста `level` записи обратно в `LogLevel` по совпадению
имени — возвращает `null`, если ключа нет или он не распознан. Вынесена в
отдельную функцию, чтобы UI-скин (как `structured_log_material`) не дублировал
этот разбор.

### `logLevelColor(LogLevel level, Brightness brightness)`

Единственный источник цветов индикатора `LogLevel`, используется строкой
списка, видом деталей и бейджами каждого скина. Живёт здесь (а не в
каком-то одном скине), потому что `Color`/`Brightness` не привязаны ни к
Material, ни к Cupertino, ни к Fluent — эта таблица действительно
design-system-нейтральна, в отличие от виджетов, построенных поверх неё.

## Построение UI-скина

`structured_log_flutter` намеренно ничего не рисует — подключайте
`LogViewerController` к любым виджетам, слушая его как обычный `ChangeNotifier`
(`AnimatedBuilder`, `ListenableBuilder` и т.п.) и читая `visibleEntries` для
отображения. Полные референс-реализации (список, детальный вид записи,
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
