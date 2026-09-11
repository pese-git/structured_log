# structured_log_material

*Read in [English](README.md).*

Готовый к использованию in-app просмотрщик логов на Material 3 для
[`structured_log`](../structured_log), построенный поверх `LogViewerController`
из [`structured_log_flutter`](../structured_log_flutter): живой список (новые
сверху) с поиском, фильтрами по категории и уровню, bottom sheet с полным
контекстом записи и копированием, empty-состояние, различающее «логов ещё
нет» и «нет записей по текущему фильтру». Доступен и как полный экран
(`MaterialLogViewerPage`), и как обычный встраиваемый виджет
(`MaterialLogViewer`) — чтобы вставить его в уже существующую хрому
страницы: вкладку, боковую панель, диалог и т.п.

> **Статус:** пока не опубликован на pub.dev (`0.1.0-dev.1`, `publish_to: none`
> — зависит от тоже неопубликованного `structured_log_flutter` через path).
> Дизайн-референс: canvas
> [Log Viewer UI Concepts](https://claude.ai/code/artifact/400091b3-da51-4f73-a1fb-2ce779515de0)
> (раздел Material — Cupertino/Fluent там только макеты, без реализации).

## Возможности

- **`MaterialLogViewer`** — просмотрщик логов как обычный встраиваемый
  виджет: панель управления (поле поиска, пауза/возобновление, очистка)
  над чипами фильтров по категории и уровню и живым списком (новые
  сверху) — без собственной хромы страницы, поэтому его можно вставить в
  любой layout
- **`MaterialLogViewerPage`** — тонкая обёртка `Scaffold`/`AppBar` вокруг
  `MaterialLogViewer` для полноэкранного сценария: добавляет заголовок
  («Logs») и, при пуше через `Navigator`, кнопку «назад» (штатную для
  `AppBar`)
- **Адаптивность** — то, как показывается контекст выбранной записи,
  реагирует на ширину, выделенную *самому виджету* (а не окну): ниже
  брейкпоинта master-detail (мобильный сценарий по умолчанию) тап по
  строке открывает `LogEntryDetailSheet` как модальный bottom sheet; на
  и выше него список и немодальная `LogEntryDetailPanel` показываются
  рядом — по гайдлайнам Material для list-detail на планшете и десктопе
- **`LogCategoryChips`** — ряд чипов фильтра по `category`, варианты
  которого берутся из уникальных значений `category`, реально
  присутствующих в буфере; скрывается автоматически, если их меньше двух
- **`LogEntryTile`** — одна строка: цветной индикатор уровня, `event`,
  отформатированное время и тег категории, если он задан; подсвечивается,
  когда её запись показана в соседней `LogEntryDetailPanel`
- **`LogEntryDetailSheet`** — тап по строке (на узких экранах) показывает
  весь контекст записи как пары ключ-значение в модальном bottom sheet, с
  действием «Copy context»
- **`LogEntryDetailPanel`** — тот же контент контекста/копирования, что и
  `LogEntryDetailSheet`, но как немодальная панель для широкоэкранного
  master-detail split — без ручки для свайпа и кнопки «Close»
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

Чтобы встроить просмотрщик в уже существующую хрому страницы, а не
отдавать ему весь экран, используйте `MaterialLogViewer` напрямую:

```dart
Row(
  children: [
    Expanded(child: MyAppContent()),
    SizedBox(
      width: 420,
      child: MaterialLogViewer(controller: controller),
    ),
  ],
)
```

## Справочник API

| Виджет | Описание |
|---|---|
| `MaterialLogViewer({required LogViewerController controller})` | Просмотрщик логов как встраиваемый виджет (без хромы страницы) |
| `MaterialLogViewerPage({required LogViewerController controller})` | Полный экран |
| `LogCategoryChips({required LogViewerController controller, String allLabel = 'All'})` | Ряд чипов фильтра по категории |
| `LogEntryTile({required entry, required onTap, bool selected = false})` | Одна строка списка |
| `LogEntryDetailSheet({required entry})` | Содержимое bottom sheet развёрнутой записи (узкие экраны) |
| `LogEntryDetailPanel({required entry})` | Содержимое немодальной панели развёрнутой записи (широкие экраны) |
| `LogViewerEmptyState({required hasLogs, required onClearFilters})` | Empty-состояние с двумя вариантами |
| `logLevelColor(LogLevel level, Brightness brightness)` | Канонический цвет индикатора уровня — единственное место, где определена эта палитра |

`entry` везде — это `Map<String, dynamic>` в том же виде, в котором его
отдаёт `structured_log` напрямую, без отдельной типизированной модели.

## Лицензия

MIT
