# structured_log_fluent

*Read in [English](README.md).*

Готовый к использованию in-app просмотрщик логов на Fluent UI
(WinUI-style) для [`structured_log`](../structured_log), построенный
поверх `LogViewerController` из
[`structured_log_flutter`](../structured_log_flutter): master-detail
split view (список слева, полный контекст выбранной записи в панели
справа — как в WinUI-приложениях вроде Почты/Параметров, а не мобильный
bottom sheet), поле поиска, выпадающие списки фильтров по категории и
уровню — всё оформлено через `FluentTheme` для светлой и тёмной темы.
Доступен и как полный экран (`FluentLogViewerPage`), и как обычный
встраиваемый виджет (`FluentLogViewer`) — чтобы вставить его в уже
существующую хрому страницы: `Flyout`, боковую панель, вкладку и т.п.

> **Статус:** пока не опубликован на pub.dev (`0.1.0-dev.1`, `publish_to:
> none` — зависит от тоже неопубликованного `structured_log_flutter` через
> path). `fluent_ui` зафиксирован точной версией (см.
> [pubspec.yaml](pubspec.yaml)), а не диапазоном — последний опубликованный
> релиз компилируется не на каждом Flutter SDK; бампать осознанно.
> Дизайн-референс: canvas
> [Log Viewer UI Concepts](https://claude.ai/code/artifact/400091b3-da51-4f73-a1fb-2ce779515de0)
> (раздел Fluent).

## Возможности

- **`FluentLogViewer`** — просмотрщик логов как обычный встраиваемый
  виджет: панель управления (поле поиска, выпадающий список категорий,
  выпадающий список уровня, пауза/возобновление, очистка) над живым
  списком (новые сверху) с панелью деталей выбранной записи — без
  собственной хромы страницы, поэтому его можно вставить в любой layout
- **`FluentLogViewerPage`** — тонкая обёртка `ScaffoldPage` вокруг
  `FluentLogViewer` для полноэкранного сценария: добавляет заголовок
  («Logs») и, при пуше через `Navigator`, кнопку «назад»
- **`LogCategoryComboBox`** — выпадающий список фильтра по `category`,
  варианты которого берутся из уникальных значений `category`, реально
  присутствующих в буфере; скрывается автоматически, если их меньше двух
- **`LogEntryTile`** — одна строка: цветной бейдж уровня, `event`,
  отформатированное время и тег категории, если он задан; hover- и
  accent-подсветка выбранной строки
- **`LogEntryDetailPane`** — полный контекст выбранной записи как пары
  ключ-значение с действием «Copy» — отображается рядом со списком
  (master-detail), а не как модальное перекрытие
- **`LogViewerEmptyState`** — «No logs yet» против «No results found» (с
  действием «Clear filters»)
- **Следует теме** — цвета и типографика из `FluentTheme.of`/
  `theme.resources` (светлая/тёмная поддержаны); фиксирована только
  палитра индикаторов уровня (`logLevelColor`), живёт в одном месте, чтобы
  не расходиться между виджетами

## Установка

Внутри этого monorepo:

```yaml
dependencies:
  fluent_ui: 4.15.1
  structured_log_flutter:
    path: ../structured_log_flutter
  structured_log_fluent:
    path: ../structured_log_fluent
```

## Быстрый старт

```dart
import 'package:fluent_ui/fluent_ui.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart';
import 'package:structured_log_fluent/structured_log_fluent.dart';

void main() {
  final buffer = LogBuffer();
  final controller = LogViewerController(buffer);

  StructlogConfiguration.configure(sinks: [
    LogSink(name: 'viewer', output: buffer.capture),
  ]);

  runApp(FluentApp(
    home: FluentLogViewerPage(controller: controller),
  ));
}
```

Полноценное запускаемое приложение (включая web) — в [`example/`](example/),
запуск через `flutter run -d chrome` из этой директории.

Чтобы встроить просмотрщик в уже существующую хрому страницы, а не
отдавать ему весь экран, используйте `FluentLogViewer` напрямую:

```dart
Row(
  children: [
    Expanded(child: MyAppContent()),
    SizedBox(
      width: 420,
      child: FluentLogViewer(controller: controller),
    ),
  ],
)
```

## Справочник API

| Виджет | Описание |
|---|---|
| `FluentLogViewer({required LogViewerController controller})` | Просмотрщик логов как встраиваемый виджет (без хромы страницы) |
| `FluentLogViewerPage({required LogViewerController controller})` | Полный экран |
| `LogCategoryComboBox({required LogViewerController controller, String allLabel = 'All types'})` | Выпадающий список фильтра по категории |
| `LogEntryTile({required entry, required selected, required onTap})` | Одна строка списка |
| `LogEntryDetailPane({required entry})` | Содержимое панели деталей |
| `LogViewerEmptyState({required hasLogs, required onClearFilters})` | Empty-состояние с двумя вариантами |
| `logLevelColor(LogLevel level, Brightness brightness)` | Канонический цвет индикатора уровня |
| `logLevelAbbreviation(LogLevel level)` | Короткая аббревиатура заглавными (`INF`, `WRN`, ...) для бейджа уровня |

`entry` везде — это `Map<String, dynamic>` в том же виде, в котором его
отдаёт `structured_log` напрямую, без отдельной типизированной модели.

## Лицензия

MIT
