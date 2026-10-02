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

> **Статус:** опубликован на [pub.dev](https://pub.dev/packages/structured_log_fluent)
> (`0.1.0`). `fluent_ui` требует Flutter `3.44.0+` — это проверяет
> собственный `environment.flutter`-констрейнт пакета (см.
> [pubspec.yaml](pubspec.yaml)), так что на более старом Flutter SDK `pub
> get` упадёт сразу, а не сборка где-то глубоко внутри `fluent_ui`.
> Эталон дизайна: canvas
> [Log Viewer UI Concepts](https://claude.ai/code/artifact/400091b3-da51-4f73-a1fb-2ce779515de0)
> (раздел Fluent).

## Возможности

- **`FluentLogViewer`** — просмотрщик логов как обычный встраиваемый
  виджет: панель управления (поле поиска, выпадающий список категорий,
  выпадающий список уровня, пауза/возобновление, очистка) над живым
  списком (новые сверху) с панелью деталей выбранной записи — без
  собственной хромы страницы, поэтому его можно вставить в любую раскладку
- **Адаптивная вёрстка** — и панель управления, и master-detail split
  зависят от ширины, которую получил *сам виджет*, а не окно: узкая
  панель управления переносится на вторую строку, а не переполняется, а
  узкий master-detail сворачивается в одну панель (список; тап по записи
  показывает её детали на месте списка, с кнопкой «назад»), — так что
  виджетом можно пользоваться и в узкой боковой панели, а не только на
  весь экран
- **`FluentLogViewerPage`** — тонкая обёртка `ScaffoldPage` вокруг
  `FluentLogViewer` для полноэкранного сценария: добавляет заголовок
  («Logs») и, при пуше через `Navigator`, кнопку «назад»
- **`LogCategoryComboBox`** — выпадающий список фильтра по `category`,
  варианты которого берутся из уникальных значений `category`, реально
  присутствующих в буфере; скрывается автоматически, если их меньше двух
- **`LogEntryTile`** — одна строка: цветной бейдж уровня, `event`,
  отформатированное время и тег категории, если он задан; подсветка при
  наведении и акцентная подсветка выбранной строки
- **`LogEntryDetailPane`** — полный контекст выбранной записи как пары
  ключ-значение с действием «Copy» — отображается рядом со списком
  (master-detail), а не модальным окном поверх него
- **`LogViewerEmptyState`** — «No logs yet» либо «No results found» (с
  действием «Clear filters»)
- **Следует теме** — цвета и типографика из `FluentTheme.of`/
  `theme.resources` (светлая/тёмная поддержаны); фиксирована только
  палитра индикаторов уровня (`logLevelColor`); она задана в одном месте,
  чтобы не расходиться между виджетами

## Установка

```yaml
dependencies:
  structured_log_fluent: ^0.1.0
```

Внутри этого monorepo `melos bootstrap` подставляет вместо двух
внутренних зависимостей path-зависимости:

```yaml
dependencies:
  fluent_ui: ^4.16.1
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

## Скриншоты

`FluentLogViewerPage` на весь экран — master-detail split: список
слева с тулбаром поиска и фильтров по категории/уровню над ним, полный
контекст выбранной записи справа:

![FluentLogViewerPage: живой список записей с цветными бейджами уровня слева, поле поиска и ComboBox-фильтры категории/уровня над ним, полный контекст выбранной записи с действием копирования справа](doc/screenshots/full-screen.png)

`FluentLogViewer`, встроенный в боковую панель рядом с остальным
контентом приложения — тот же виджет, без собственной хромы страницы:

![FluentLogViewer в боковой панели с flex 2:1 рядом с заглушкой контента приложения — тот же список логов и панель деталей](doc/screenshots/embedded.png)

На экране шириной с телефон тулбар переносится на вторую строку, а
master-detail split сворачивается в список; тап по записи заменяет
список на `LogEntryDetailPane` с собственной ссылкой «назад»:

![FluentLogViewerPage на узком экране шириной с телефон: тулбар перенесён на две строки сверху, список заменён полным контекстом записи, по которой тапнули, со ссылкой «назад» и действием копирования](doc/screenshots/mobile.png)

## Справочник API

| Виджет | Описание |
|---|---|
| `FluentLogViewer({required LogViewerController controller})` | Просмотрщик логов как встраиваемый виджет (без хромы страницы) |
| `FluentLogViewerPage({required LogViewerController controller})` | Полный экран |
| `LogCategoryComboBox({required LogViewerController controller, String allLabel = 'All types'})` | Выпадающий список фильтра по категории |
| `LogEntryTile({required entry, required selected, required onTap})` | Одна строка списка |
| `LogEntryDetailPane({required entry})` | Содержимое панели деталей |
| `LogViewerEmptyState({required hasLogs, required onClearFilters})` | Empty-состояние с двумя вариантами |
| `logLevelColor(LogLevel level, Brightness brightness)` | Канонический цвет индикатора уровня — определён один раз в `structured_log_flutter`, общий для всех скинов |
| `logLevelAbbreviation(LogLevel level)` | Короткая аббревиатура заглавными (`INF`, `WRN`, ...) для бейджа уровня |

`entry` везде — это `Map<String, dynamic>` в том же виде, в котором его
отдаёт `structured_log` напрямую, без отдельной типизированной модели.

## Связанные пакеты

Остальные пакеты семейства `structured_log`:

**Ядро**

- [`structured_log`](https://pub.dev/packages/structured_log) — структурированное JSON-логирование с привязкой контекста, процессорами и маршрутизацией по синкам

**Просмотрщик логов в приложении**

- [`structured_log_flutter`](https://pub.dev/packages/structured_log_flutter) — headless-ядро просмотрщика: `LogBuffer` и `LogViewerController`
- [`structured_log_material`](https://pub.dev/packages/structured_log_material) — просмотрщик на Material 3
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
