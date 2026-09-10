# structured_log_flutter

*Read in [English](README.md).*

Headless-ядро просмотрщика логов для [`structured_log`](../structured_log) —
буфер ограниченного размера и фильтрующий контроллер для построения живого
in-app просмотрщика логов во Flutter. Никакой зависимости от Material,
Cupertino или любой другой дизайн-системы: пакет сам ничего не рисует, так что
поверх него можно построить любой UI-скин. [`structured_log_material`](../structured_log_material)
— первый такой скин.

> **Статус:** пока не опубликован на pub.dev (`0.1.0-dev.1`). Подключайте как
> path-зависимость внутри этого monorepo.

## Возможности

- **`LogBuffer`** — кольцевой буфер фиксированной ёмкости, подключается напрямую
  к `structured_log` как `OutputFunction`/`LogSink.output`
- **Живые обновления** — `LogBuffer.entries` это `ValueListenable`, виджет может
  перерисовываться на каждую новую запись без опроса
- **`LogViewerController`** — `ChangeNotifier` с фильтрацией по уровню/категории/
  тексту поиска, паузой/возобновлением и очисткой поверх `LogBuffer`
- **Ноль зависимостей от дизайн-системы** — только `package:flutter/foundation.dart`
  и `structured_log`

## Установка

Внутри этого monorepo:

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

## Построение UI-скина

`structured_log_flutter` намеренно ничего не рисует — подключайте
`LogViewerController` к любым виджетам, слушая его как обычный `ChangeNotifier`
(`AnimatedBuilder`, `ListenableBuilder` и т.п.) и читая `visibleEntries` для
отображения. Полную референс-реализацию (список, детальный вид записи,
empty-состояния) на Material 3 смотрите в
[`structured_log_material`](../structured_log_material).

## Лицензия

MIT
