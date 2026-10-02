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

Детали выбранной записи показываются адаптивно — по соглашениям iOS для
каждого размера экрана, а не по одному образцу для всех: ниже брейкпоинта по ширине (мобильный сценарий по умолчанию) тап по
строке **пушит** новый экран через `CupertinoPageRoute` — стандартный
iOS-паттерн «переход в детали» (как в Почте/Настройках на iPhone); на и
выше него список и немодальная панель деталей показываются рядом — так
ведут себя те же приложения на iPad.

> **Статус:** опубликован на [pub.dev](https://pub.dev/packages/structured_log_cupertino)
> (`0.1.0`). История дизайна и решений:
> [openspec/changes/archive/2026-10-01-add-structured-log-cupertino/](../../openspec/changes/archive/2026-10-01-add-structured-log-cupertino/).

## Возможности

- **`CupertinoLogViewer`** — просмотрщик логов как обычный встраиваемый
  виджет: панель управления (`CupertinoSearchTextField`,
  пауза/возобновление, очистка) над рядом чипов фильтра по категории и
  `CupertinoSlidingSegmentedControl` фильтра по уровню, над живым списком
  (новые сверху) — без собственной хромы страницы, поэтому его можно
  вставить в любую раскладку
- **`CupertinoLogViewerPage`** — тонкая обёртка `CupertinoPageScaffold`
  вокруг `CupertinoLogViewer` для полноэкранного сценария: добавляет
  navigation bar с заголовком «Logs» и, при пуше через `Navigator`, кнопку
  «назад» (штатную для `CupertinoNavigationBar`)
- **Адаптивность** — узкие экраны: список + пушенный экран
  `LogEntryDetailPanel` по тапу (паттерн iPhone); широкие экраны: список и
  немодальная `LogEntryDetailPanel` рядом (паттерн iPad) — зависит от
  ширины, которую получил *сам виджет*, а не окно
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
- **`LogViewerEmptyState`** — «No logs yet» либо «No logs match the
  current filter» (с действием «Clear filters»)
- **Следует теме** — цвета и типографика берутся из `CupertinoTheme.of`/
  `CupertinoColors` (светлая/тёмная поддержаны через `resolveFrom`);
  фиксирована только палитра индикаторов уровня (`logLevelColor`), общая
  для всех скинов через `structured_log_flutter`

## Установка

```yaml
dependencies:
  structured_log_cupertino: ^0.1.0
```

Внутри этого monorepo `melos bootstrap` подставляет вместо обеих
path-зависимости:

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

## Скриншоты

`CupertinoLogViewerPage` на весь экран, на широком/iPad-размере
экрана — список и немодальная панель деталей рядом:

![CupertinoLogViewerPage: живой список записей с цветными точками уровня слева, поле поиска и фильтры категории/уровня над ним, полный контекст выбранной записи с действием копирования справа](doc/screenshots/full-screen.png)

`CupertinoLogViewer`, встроенный в боковую панель рядом с остальным
контентом приложения — тот же виджет, без собственной хромы страницы:

![CupertinoLogViewer в боковой панели с flex 2:1 рядом с заглушкой контента приложения — тот же список логов и панель деталей](doc/screenshots/embedded.png)

На экране шириной с телефон — мобильный сценарий по умолчанию —
список сам по себе, а тап по записи **пушит** `LogEntryDetailPanel`
отдельным экраном через `CupertinoPageRoute` — стандартный iOS-паттерн
«переход в детали»:

![CupertinoLogViewerPage на узком экране шириной с телефон: запись, по которой тапнули, запушена отдельным экраном — шеврон «назад», заголовок записи в navigation bar, её полный контекст и действие копирования](doc/screenshots/mobile.png)

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

## Связанные пакеты

Остальные пакеты семейства `structured_log`:

**Ядро**

- [`structured_log`](https://pub.dev/packages/structured_log) — структурированное JSON-логирование с привязкой контекста, процессорами и маршрутизацией по синкам

**Просмотрщик логов в приложении**

- [`structured_log_flutter`](https://pub.dev/packages/structured_log_flutter) — headless-ядро просмотрщика: `LogBuffer` и `LogViewerController`
- [`structured_log_material`](https://pub.dev/packages/structured_log_material) — просмотрщик на Material 3
- [`structured_log_fluent`](https://pub.dev/packages/structured_log_fluent) — просмотрщик на Fluent UI (в стиле WinUI)

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
