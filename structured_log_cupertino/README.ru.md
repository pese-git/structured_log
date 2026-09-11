# structured_log_cupertino

*Read in [English](README.md).*

Готовый к использованию in-app просмотрщик логов на Cupertino (iOS-style)
для [`structured_log`](../structured_log), построенный поверх
`LogViewerController` из
[`structured_log_flutter`](../structured_log_flutter): живой список (новые
сверху) с поиском, фильтрами по категории и уровню, вид деталей записи с
полным контекстом и копированием, empty-состояние, различающее «логов ещё
нет» и «нет записей по текущему фильтру». Доступен и как полный экран
(`CupertinoLogViewerPage`), и как обычный встраиваемый виджет
(`CupertinoLogViewer`) — чтобы вставить его в уже существующую хрому
страницы: вкладку, боковую панель и т.п.

То, как показываются детали выбранной записи, адаптивно и следует
конвенциям iOS на каждом размере экрана, а не выбирает один паттерн для
всех: ниже брейкпоинта по ширине (мобильный сценарий по умолчанию) тап по
строке **пушит** новый экран через `CupertinoPageRoute` — стандартный
iOS-паттерн «переход в детали» (как в Почте/Настройках на iPhone); на и
выше него список и немодальная панель деталей показываются рядом — как те
же приложения ведут себя на iPad.

> **Статус:** пока не опубликован на pub.dev (`0.1.0-dev.1`), но больше не
> заблокирован технически — `publish_to: none` снят, пакет провалидирован
> (`dart pub publish --dry-run` проходит; `CHANGELOG.md` появится, когда
> прогонят `melos version`, см. [AGENTS.md](../AGENTS.md)). История дизайна
> и решений:
> [openspec/changes/add-structured-log-cupertino/](../openspec/changes/add-structured-log-cupertino/).

## Возможности

- **`CupertinoLogViewer`** — просмотрщик логов как обычный встраиваемый
  виджет: панель управления (`CupertinoSearchTextField`,
  пауза/возобновление, очистка) над рядом чипов фильтра по категории и
  `CupertinoSlidingSegmentedControl` фильтра по уровню, над живым списком
  (новые сверху) — без собственной хромы страницы, поэтому его можно
  вставить в любой layout
- **`CupertinoLogViewerPage`** — тонкая обёртка `CupertinoPageScaffold`
  вокруг `CupertinoLogViewer` для полноэкранного сценария: добавляет
  navigation bar с заголовком «Logs» и, при пуше через `Navigator`, кнопку
  «назад» (штатную для `CupertinoNavigationBar`)
- **Адаптивность** — узкие экраны: список + пушенный экран
  `LogEntryDetailPanel` по тапу (паттерн iPhone); широкие экраны: список и
  немодальная `LogEntryDetailPanel` рядом (паттерн iPad) — реагирует на
  ширину, выделенную *самому виджету*, а не окну
- **`LogCategoryFilterBar`** — горизонтально прокручиваемый ряд
  pill-кнопок фильтра по `category`, варианты которого берутся из
  уникальных значений, реально присутствующих в буфере; скрывается
  автоматически, если их меньше двух (`CupertinoSlidingSegmentedControl`
  не годится для динамического открытого набора опций — он используется
  для фильтра уровня, у которого набор маленький и фиксированный)
- **`LogEntryTile`** — одна строка: цветная точка уровня, `event`,
  отформатированное время и тег категории, если он задан; шеврон справа на
  узких экранах (переход на пушенный экран деталей), вместо него —
  подсветка, когда запись показана в соседней панели на широких экранах
- **`LogEntryDetailPanel`** — полный контекст выбранной записи как пары
  ключ-значение с действием «Copy» — обычный немодальный виджет (без ручки
  для свайпа, без кнопки «Close»), переиспользуется и при пуше отдельным
  экраном, и внутри master-detail split
- **`LogViewerEmptyState`** — «No logs yet» против «No logs match the
  current filter» (с действием «Clear filters»)
- **Следует теме** — цвета и типографика берутся из `CupertinoTheme.of`/
  `CupertinoColors` (светлая/тёмная поддержаны через `resolveFrom`);
  фиксирована только палитра индикаторов уровня (`logLevelColor`), общая
  для всех скинов через `structured_log_flutter`

## Установка

Внутри этого monorepo:

```yaml
dependencies:
  structured_log_flutter:
    path: ../structured_log_flutter
  structured_log_cupertino:
    path: ../structured_log_cupertino
```

## Быстрый старт

```dart
import 'package:flutter/cupertino.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart';
import 'package:structured_log_cupertino/structured_log_cupertino.dart';

void main() {
  final buffer = LogBuffer();
  final controller = LogViewerController(buffer);

  StructlogConfiguration.configure(sinks: [
    LogSink(name: 'viewer', output: buffer.capture),
  ]);

  runApp(CupertinoApp(
    home: CupertinoLogViewerPage(controller: controller),
  ));
}
```

Полноценное запускаемое приложение (включая web) — в [`example/`](example/),
запуск через `flutter run -d chrome` из этой директории.

Чтобы встроить просмотрщик в уже существующую хрому страницы, а не
отдавать ему весь экран, используйте `CupertinoLogViewer` напрямую:

```dart
Row(
  children: [
    Expanded(child: MyAppContent()),
    SizedBox(
      width: 420,
      child: CupertinoLogViewer(controller: controller),
    ),
  ],
)
```

## Справочник API

| Виджет | Описание |
|---|---|
| `CupertinoLogViewer({required LogViewerController controller})` | Просмотрщик логов как встраиваемый виджет (без хромы страницы) |
| `CupertinoLogViewerPage({required LogViewerController controller})` | Полный экран |
| `LogCategoryFilterBar({required LogViewerController controller, String allLabel = 'All'})` | Ряд pill-кнопок фильтра по категории |
| `LogEntryTile({required entry, required onTap, bool selected = false, bool showsDisclosureIndicator = true})` | Одна строка списка |
| `LogEntryDetailPanel({required entry})` | Содержимое деталей записи с полным контекстом (пушится или показывается рядом) |
| `LogViewerEmptyState({required hasLogs, required onClearFilters})` | Empty-состояние с двумя вариантами |
| `logLevelColor(LogLevel level, Brightness brightness)` | Канонический цвет индикатора уровня — определён один раз в `structured_log_flutter`, общий для всех скинов |

`entry` везде — это `Map<String, dynamic>` в том же виде, в котором его
отдаёт `structured_log` напрямую, без отдельной типизированной модели.

## Лицензия

MIT
