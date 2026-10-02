# structured_log_cupertino

[![CI](https://github.com/pese-git/structured_log/actions/workflows/ci.yml/badge.svg)](https://github.com/pese-git/structured_log/actions/workflows/ci.yml)

*Read in [English](README.md).*

**Готовый просмотрщик логов на Cupertino (в стиле iOS) для
Flutter-приложения: откройте экран или боковую панель — и увидите, что
приложение только что записало в лог, с поиском, фильтрами и полным
контекстом каждой записи, так, как это принято на iPhone и iPad.**

## Зачем

Во время проверки на iPhone что-то идёт не так, а объяснение лежит в логах,
которые печатаются в консоль Xcode, — а к ней вы не подключены. Этот пакет
выводит логи на экран прямо в приложении: все записи
[`structured_log`](https://pub.dev/packages/structured_log), новые сверху, с
поиском и фильтрами по уровню и категории; тап по записи открывает её
полный контекст, который можно скопировать в отчёт об ошибке. Подключение —
один дополнительный синк и один виджет.

Этот скин — для приложений в стиле iOS (`CupertinoApp` или
Cupertino-экраны внутри большого приложения). Для приложения на Material
берите
[`structured_log_material`](https://pub.dev/packages/structured_log_material),
для десктопного приложения в стиле Windows на `fluent_ui` —
[`structured_log_fluent`](https://pub.dev/packages/structured_log_fluent).
Если ни один из трёх не подходит к вашей дизайн-системе, соберите свой на
[`structured_log_flutter`](https://pub.dev/packages/structured_log_flutter):
скины построены на нём, поэтому фильтры и пауза везде ведут себя одинаково.

## Возможности

### Готов к встраиванию

- **Экран или панель** — `CupertinoLogViewerPage` — готовый
  `CupertinoPageScaffold` с навигационной панелью «Logs» (и штатной кнопкой
  «назад», если его открыли через `Navigator`); `CupertinoLogViewer` — тот
  же просмотрщик без хромы страницы, для вкладки или боковой панели.
- **Как на iPhone и как на iPad** — ориентируется на собственную ширину, а
  не на ширину окна: если она меньше 700 логических пикселей, тап
  **открывает** запись отдельным экраном через `CupertinoPageRoute`, как
  Почта и Настройки на iPhone; начиная с 700 список и панель деталей стоят
  рядом, как на iPad, и выбрана самая новая запись.

### Поиск нужной записи

- **Живой список, новые сверху** — записи появляются по мере того, как
  приложение их пишет.
- **Поиск** — `CupertinoSearchTextField` по именам событий и всем
  значениям контекста.
- **Фильтр по уровню** — `CupertinoSlidingSegmentedControl`: All, Debug+,
  Info+, Warning+, Error+.
- **Фильтр по категории** — прокручиваемый ряд кнопок-«таблеток» из
  категорий, которые реально есть в буфере; пока их меньше двух, ряд скрыт.
  Записи адаптеров вроде
  [`structured_log_dio`](https://pub.dev/packages/structured_log_dio) (`http`)
  или [`structured_log_bloc`](https://pub.dev/packages/structured_log_bloc)
  (`bloc`) сами собой становятся фильтром.
- **Пауза и очистка** — заморозьте список, пока читаете; очистите его
  перед новым воспроизведением.
- **Привычные строки** — цветная точка уровня, событие, время и тег
  категории; шеврон там, где тап открывает новый экран, и подсветка там,
  где он выбирает запись.

### Чтение записи

- **Полный контекст** — сверху уровень, время и событие, ниже все
  остальные поля парами ключ-значение; на отдельном экране имя события
  стоит в заголовке.
- **Копирование** — один тап кладёт поля в буфер обмена строками
  `key: value`.
- **Понятные пустые состояния** — «No logs yet», если ничего не захвачено,
  и «No logs match the current filter» с действием «Clear filters», если
  всё скрыли фильтры.

### Выглядит как ваше приложение

- **Следует теме** — цвета и типографика берутся из `CupertinoTheme` и
  `CupertinoColors`, светлая и тёмная темы поддержаны; фиксированы только
  цвета уровней, и они одинаковы во всех скинах.
- **Без Material** — пакет использует только виджеты Cupertino и
  `cupertino_icons`.
- **Детали для своей раскладки** — `LogEntryTile`, `LogCategoryFilterBar`,
  `LogEntryDetailPanel` и `LogViewerEmptyState` публичны.

## Место в проекте

[`structured_log`](https://pub.dev/packages/structured_log) пишет записи;
[`structured_log_flutter`](https://pub.dev/packages/structured_log_flutter)
держит последние из них в памяти и отвечает за фильтры и паузу; этот пакет —
Cupertino-оболочка поверх, рядом с
[`structured_log_material`](https://pub.dev/packages/structured_log_material)
и [`structured_log_fluent`](https://pub.dev/packages/structured_log_fluent).
Он работает целиком внутри приложения, без сервера; если вы вдобавок
отправляете логи на self-hosted сервер через
[`structured_log_remote_sync`](https://pub.dev/packages/structured_log_remote_sync),
просмотрщик по-прежнему показывает их на месте. Подробнее — в документации на
[structured-log.openidealab.com](https://structured-log.openidealab.com/ru/)
и в [руководстве по встраиванию](https://structured-log.openidealab.com/ru/guides/embedding-guide/).
История дизайна и решений —
[openspec/changes/archive/2026-10-01-add-structured-log-cupertino/](https://github.com/pese-git/structured_log/tree/master/openspec/changes/archive/2026-10-01-add-structured-log-cupertino).

## Установка

```yaml
dependencies:
  structured_log: ^0.3.0
  structured_log_flutter: ^0.1.2
  structured_log_cupertino: ^0.1.1
```

Внутри этого monorepo `melos bootstrap` подставляет вместо обоих
внутренних пакетов path-зависимости:

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

Полноценное запускаемое приложение (включая web) — в [`example/`](https://github.com/pese-git/structured_log/tree/master/emb/structured_log_cupertino/example),
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
