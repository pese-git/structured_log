# structured_log_fluent

[![CI](https://github.com/pese-git/structured_log/actions/workflows/ci.yml/badge.svg)](https://github.com/pese-git/structured_log/actions/workflows/ci.yml)

*Read in [English](README.md).*

**Готовый просмотрщик логов на Fluent UI (в стиле WinUI) для
Flutter-приложения: экран master-detail или встроенная панель, где видно,
что приложение только что записало в лог, — с поиском, фильтрами и полным
контекстом каждой записи.**

## Зачем

Десктопное приложение ведёт себя странно на машине тестировщика, а логи,
которые всё объяснили бы, ушли в консоль, которую никто не открывал. Этот
пакет показывает логи внутри приложения — в раскладке, знакомой
пользователям Windows по Почте и Параметрам: слева обновляемый список записей
[`structured_log`](https://pub.dev/packages/structured_log), справа полный
контекст выбранной, сверху поле поиска и выпадающие фильтры. Для подключения
нужны один дополнительный синк и один виджет.

Этот скин — для приложений на `fluent_ui`: обычно это десктоп под Windows,
хотя работает он везде, где работает Flutter, включая web. Для приложения на
Material берите
[`structured_log_material`](https://pub.dev/packages/structured_log_material),
для приложения в стиле iOS —
[`structured_log_cupertino`](https://pub.dev/packages/structured_log_cupertino).
Если ни один из трёх не подходит к вашей дизайн-системе, соберите свой на
[`structured_log_flutter`](https://pub.dev/packages/structured_log_flutter):
скины построены на нём, поэтому фильтры и пауза везде ведут себя одинаково.

## Возможности

### Встраивание в приложение

- **Экран или панель** — `FluentLogViewerPage` даёт готовый `ScaffoldPage` с
  заголовком «Logs» (и кнопкой «назад», если его открыли через
  `Navigator`); `FluentLogViewer` — тот же просмотрщик без каркаса страницы,
  для `Flyout`, боковой панели или вкладки.
- **Master-detail, как принято в WinUI** — список слева, выбранная запись
  (по умолчанию самая новая) справа, а не мобильный bottom sheet.
- **Не ломается на узкой ширине** — ориентируется на собственную ширину, а
  не на ширину окна: при ширине меньше 820 логических пикселей панель
  инструментов переносится на вторую строку, а не выходит за край, а при
  ширине меньше 640 раскладка сворачивается в список, и тап открывает
  запись на его месте с кнопкой «назад».

### Поиск нужной записи

- **Список обновляется сам, новые записи сверху** — записи появляются по
  мере того, как приложение их пишет.
- **Поиск** — по именам событий и всем значениям контекста.
- **Фильтр по уровню** — выпадающий список от «All levels» до «Error and
  above».
- **Фильтр по категории** — выпадающий список из категорий, которые
  действительно есть в буфере; пока их меньше двух, он скрыт. Записи адаптеров
  вроде [`structured_log_dio`](https://pub.dev/packages/structured_log_dio)
  (`http`) или [`structured_log_bloc`](https://pub.dev/packages/structured_log_bloc)
  (`bloc`) автоматически попадают в фильтр.
- **Пауза и очистка** — заморозьте список, пока читаете, и очистите его
  перед тем, как воспроизвести проблему снова.
- **Компактные строки** — цветной бейдж уровня (`INF`, `WRN`, `ERR`, …),
  событие, время и тег категории, подсветка при наведении и выделение
  акцентным цветом.

### Чтение записи

- **Полный контекст** — сверху уровень, время и событие, ниже все
  остальные поля парами ключ-значение.
- **Копирование** — поля копируются в буфер обмена одним кликом,
  строками `key: value`.
- **Понятные пустые состояния** — «No logs yet», если записей ещё нет,
  и «No results found» с действием «Clear filters», если все записи
  скрыты фильтрами.

### Оформление в стиле приложения

- **Следует теме** — цвета и типографика берутся из `FluentTheme`,
  поддерживаются светлая и тёмная темы; фиксированы только цвета уровней, и они
  одинаковы во всех скинах.
- **Части для собственной раскладки** — `LogEntryTile`, `LogCategoryComboBox`,
  `LogEntryDetailPane`, `LogViewerEmptyState` и `logLevelAbbreviation`
  публичны.

## Место в проекте

[`structured_log`](https://pub.dev/packages/structured_log) пишет записи;
[`structured_log_flutter`](https://pub.dev/packages/structured_log_flutter)
держит последние из них в памяти и отвечает за фильтры и паузу; этот пакет —
Fluent-оболочка поверх, рядом с
[`structured_log_material`](https://pub.dev/packages/structured_log_material)
и [`structured_log_cupertino`](https://pub.dev/packages/structured_log_cupertino).
Он работает целиком внутри приложения, без сервера; если вы, кроме того,
отправляете логи на self-hosted сервер через
[`structured_log_remote_sync`](https://pub.dev/packages/structured_log_remote_sync),
просмотрщик по-прежнему показывает их прямо в приложении. Подробнее — в документации на
[structured-log.openidealab.com](https://structured-log.openidealab.com/ru/)
и в [руководстве по встраиванию](https://structured-log.openidealab.com/ru/guides/embedding-guide/).
Эталон дизайна — canvas
[Log Viewer UI Concepts](https://claude.ai/code/artifact/400091b3-da51-4f73-a1fb-2ce779515de0)
(раздел Fluent).

## Установка

```yaml
dependencies:
  fluent_ui: ^4.16.1
  structured_log: ^0.3.0
  structured_log_flutter: ^0.1.2
  structured_log_fluent: ^0.1.1
```

`fluent_ui` требует Flutter `3.44.0+`. Это проверяет собственное
ограничение `environment.flutter` пакета (см.
[pubspec.yaml](https://github.com/pese-git/structured_log/blob/master/emb/structured_log_fluent/pubspec.yaml)),
так что на более старом Flutter SDK сразу упадёт `pub get`, а не сборка
где-то глубоко внутри `fluent_ui`.

Внутри этого monorepo `melos bootstrap` подставляет вместо двух
внутренних пакетов path-зависимости:

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

Полноценное запускаемое приложение (включая web) — в [`example/`](https://github.com/pese-git/structured_log/tree/master/emb/structured_log_fluent/example),
запуск через `flutter run -d chrome` из этой директории.

Чтобы встроить просмотрщик в уже готовую страницу со своим каркасом, а не
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

`FluentLogViewerPage` на весь экран в раскладке master-detail: список
слева с тулбаром поиска и фильтров по категории/уровню над ним, полный
контекст выбранной записи справа:

![FluentLogViewerPage: обновляемый список записей с цветными бейджами уровня слева, поле поиска и ComboBox-фильтры категории/уровня над ним, полный контекст выбранной записи с действием копирования справа](doc/screenshots/full-screen.png)

`FluentLogViewer`, встроенный в боковую панель рядом с остальным
контентом приложения — тот же виджет, без собственного каркаса страницы:

![FluentLogViewer в боковой панели с flex 2:1 рядом с заглушкой контента приложения — тот же список логов и панель деталей](doc/screenshots/embedded.png)

На экране шириной с телефон тулбар переносится на вторую строку, а
раскладка master-detail сворачивается в список; тап по записи заменяет
список на `LogEntryDetailPane` с собственной ссылкой «назад»:

![FluentLogViewerPage на узком экране шириной с телефон: тулбар перенесён на две строки сверху, список заменён полным контекстом записи, по которой тапнули, со ссылкой «назад» и действием копирования](doc/screenshots/mobile.png)

## Справочник API

| Виджет | Описание |
|---|---|
| `FluentLogViewer({required LogViewerController controller})` | Просмотрщик логов как встраиваемый виджет (без каркаса страницы) |
| `FluentLogViewerPage({required LogViewerController controller})` | Полный экран |
| `LogCategoryComboBox({required LogViewerController controller, String allLabel = 'All types'})` | Выпадающий список фильтра по категории |
| `LogEntryTile({required entry, required selected, required onTap})` | Одна строка списка |
| `LogEntryDetailPane({required entry})` | Содержимое панели деталей |
| `LogViewerEmptyState({required hasLogs, required onClearFilters})` | Пустое состояние в двух вариантах |
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
