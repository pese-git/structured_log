# structured_log_material

*Read in [English](README.md).*

Готовый к использованию in-app просмотрщик логов на Material 3 для
[`structured_log`](../structured_log), построенный поверх `LogViewerController`
из [`structured_log_flutter`](../structured_log_flutter): живой список (новые
сверху) с поиском и фильтром по уровню, bottom sheet с полным контекстом записи
и копированием, empty-состояние, различающее «логов ещё нет» и «нет записей по
текущему фильтру».

> **Статус:** пока не опубликован на pub.dev (`0.1.0-dev.1`, `publish_to: none`
> — зависит от тоже неопубликованного `structured_log_flutter` через path).
> Дизайн-референс: canvas
> [Log Viewer UI Concepts](https://claude.ai/code/artifact/400091b3-da51-4f73-a1fb-2ce779515de0)
> (раздел Material — Cupertino/Fluent там только макеты, без реализации).

## Возможности

- **`MaterialLogViewerPage`** — полный экран: верхний app bar (заголовок, поиск,
  пауза/возобновление, очистка), чипы фильтра по уровню, живой список (новые сверху)
- **`LogEntryTile`** — одна строка: цветной индикатор уровня, `event`,
  отформатированное время и тег категории, если он задан
- **`LogEntryDetailSheet`** — тап по строке показывает весь контекст записи как
  пары ключ-значение, с действием «Copy context»
- **`LogViewerEmptyState`** — «No logs yet» (вообще ничего не захвачено) против
  «No logs match the current filter» (с действием «Clear filters»)
- **Следует теме** — цвета и типографика берутся из `Theme.of(context)`
  (поддержаны светлая и тёмная); фиксирована только палитра индикаторов уровня
  (`logLevelColor`), живёт в одном месте, чтобы не расходиться между виджетами

## Установка

Внутри этого monorepo:

```yaml
dependencies:
  structured_log_flutter:
    path: ../structured_log_flutter
  structured_log_material:
    path: ../structured_log_material
```

## Быстрый старт

```dart
import 'package:flutter/material.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart';
import 'package:structured_log_material/structured_log_material.dart';

void main() {
  final buffer = LogBuffer();
  final controller = LogViewerController(buffer);

  StructlogConfiguration.configure(sinks: [
    LogSink(name: 'viewer', output: buffer.capture),
  ]);

  runApp(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: OutlinedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => MaterialLogViewerPage(controller: controller),
              ),
            ),
            child: const Text('Open log viewer'),
          ),
        ),
      ),
    ),
  ));
}
```

Полноценное запускаемое приложение (включая web) — в [`example/`](example/),
запуск через `flutter run -d chrome` из этой директории.

## Справочник API

| Виджет | Описание |
|---|---|
| `MaterialLogViewerPage({required LogViewerController controller})` | Полный экран |
| `LogEntryTile({required entry, required onTap})` | Одна строка списка |
| `LogEntryDetailSheet({required entry})` | Содержимое bottom sheet развёрнутой записи |
| `LogViewerEmptyState({required hasLogs, required onClearFilters})` | Empty-состояние с двумя вариантами |
| `logLevelColor(LogLevel level, Brightness brightness)` | Канонический цвет индикатора уровня — единственное место, где определена эта палитра |

`entry` везде — это `Map<String, dynamic>` в том же виде, в котором его
отдаёт `structured_log` напрямую, без отдельной типизированной модели.

## Лицензия

MIT
