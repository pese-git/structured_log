# AGENTS.md

Инструкции для AI-агентов, работающих в этом репозитории.

## Проект

Репозиторий — multi-package workspace на Melos + FVM, пакеты сгруппированы по категориям
верхнего уровня (каждый пакет — директория `<категория>/<name>/`, перечисленная по полному
пути в [melos.yaml](melos.yaml)): [emb/](emb/) — встраиваемые в чужое приложение библиотеки
(`structured_log`, скины просмотрщика логов, `structured_log_http`), [backend/](backend/) —
самостоятельные серверные приложения (`structured_log_server`), [frontend/](frontend/) —
самостоятельные клиентские приложения с UI (`structured_log_admin_client`), [packages/](packages/) —
пакеты, не подпадающие однозначно ни под одну из трёх категорий выше (пока пусто, без записи
в `melos.yaml`). Первоначально раскладка была полностью плоской, без категорий — по образцу
[cherrypick](https://github.com/pese-git/cherrypick) того же автора; категории введены при
добавлении сервера и admin-клиента
([openspec/changes/add-structured-log-server/](openspec/changes/add-structured-log-server/),
decision 23) — с появлением пакетов другой природы (сервис, приложение, а не только встраиваемая
библиотека) плоский список перестал сам по себе сообщать, что чем является.

`.fvm/fvm_config.json` пинит Flutter SDK для локальной разработки/`melos`-команд
явной версией (`"flutterSdkVersion"`, сейчас `3.44.9`) — не строкой `"stable"`,
чтобы версия не «уезжала» молча при `fvm install`/`fvm use stable` без явного
решения контрибьютора. **CI на этот пин не смотрит**: `.github/workflows/ci.yml`
использует `dart-lang/setup-dart`/`subosito/flutter-action` с каналом `stable`
напрямую (без FVM), так что CI всегда гоняется на актуальном на момент запуска
`stable`-релизе — если локальный пин отстанет от него надолго, локальная
разработка и CI могут разойтись по версии SDK. Поднимать локальный пин —
`fvm use <version>` из корня репозитория, затем `dart run melos bootstrap` и
полный прогон `analyze`/`test` по всем пакетам.

Шесть пакетов в `emb/`:

- [emb/structured_log/](emb/structured_log/) — структурированное логирование для Dart, вдохновлено
  Python `structlog`, без сторонних runtime-зависимостей (кроме `meta`). Опубликован на pub.dev.
- [emb/structured_log_flutter/](emb/structured_log_flutter/) — headless-ядро для in-app просмотра логов
  во Flutter (`LogBuffer`, `LogViewerController`, `logLevelColor()`); не зависит ни от какой
  конкретной дизайн-системы. Опубликован на pub.dev.
- [emb/structured_log_material/](emb/structured_log_material/) — Material 3 виджет просмотрщика логов
  поверх `structured_log_flutter`. Разрешена публикация на pub.dev (`publish_to: none` снят).
- [emb/structured_log_fluent/](emb/structured_log_fluent/) — Fluent UI (WinUI-style) виджет просмотрщика
  логов поверх `structured_log_flutter` (master-detail вместо bottom sheet). Разрешена
  публикация на pub.dev (`publish_to: none` снят).
- [emb/structured_log_cupertino/](emb/structured_log_cupertino/) — Cupertino (iOS-style) виджет
  просмотрщика логов поверх `structured_log_flutter` (pushed-экран деталей на узких экранах,
  master-detail split на широких/iPad). Разрешена публикация на pub.dev (`publish_to: none` снят).
- [emb/structured_log_http/](emb/structured_log_http/) — `HttpLogOutput`: `LogSink`-вывод,
  отправляющий записи на `structured_log_server` по HTTP (батчинг по размеру/таймауту, retry с
  backoff, ограниченный буфер с вытеснением самых старых записей, `flushed`). Единственная
  зависимость — `structured_log`; транспорт — `dart:io` `HttpClient`, без `dio`/`http`.
  Реализован (раздел 9 `tasks.md`); `README.md` ещё нет — это задача 16.1.

Плюс один пакет в `backend/`:

- [backend/structured_log_server/](backend/structured_log_server/) — self-hosted сервер приёма/
  хранения/поиска/живой трансляции логов (`shelf`+`shelf_router`, `drift`/SQLite). Скаффолдинг
  (Этап 0, пустой публичный API); реализация — разделы 2–8/21/26/28/33/34 `tasks.md` в
  [openspec/changes/add-structured-log-server/](openspec/changes/add-structured-log-server/).
  `publish_to: none` — самостоятельный сервис, не библиотека для встраивания.

`frontend/` и `packages/` пока пусты (`structured_log_admin_client`/`structured_log_admin_ui`
появятся там по мере реализации Этапа 1 той же change).

`structured_log_material`/`structured_log_fluent`/`structured_log_cupertino` фактически ещё не
опубликованы (нет `CHANGELOG.md` — публикация требует прогнать `melos version` первым, см.
«Коммиты и версионирование» ниже), но больше не заблокированы технически: зависимость на
`structured_log_flutter` в их `pubspec.yaml` — обычный hosted-констрейнт (`^0.1.0-dev.2`),
путь к нему при локальной разработке подставляет `melos bootstrap` через
`pubspec_overrides.yaml` (генерируется, не коммитится — см. `.gitignore`). Их `example/`
остаются `publish_to: none` — демо-приложения не публикуются. История и обоснование
решений — в
[openspec/changes/add-structured-log-flutter/](openspec/changes/add-structured-log-flutter/),
[openspec/changes/add-structured-log-fluent/](openspec/changes/add-structured-log-fluent/) и
[openspec/changes/add-structured-log-cupertino/](openspec/changes/add-structured-log-cupertino/)
(`proposal.md`/`design.md`/`specs/`/`tasks.md` — по `tasks.md` можно свериться, что уже сделано).

## Структура

Верхний уровень репозитория:

- [README.md](README.md) / [README.ru.md](README.ru.md) — обзор workspace целиком, для внешних читателей.
- [emb/structured_log/](emb/structured_log/) — пакет структурированного логирования (см. ниже).
- [emb/structured_log_flutter/](emb/structured_log_flutter/) — headless-ядро просмотрщика логов (см. ниже).
- [emb/structured_log_material/](emb/structured_log_material/) — Material-скин просмотрщика логов (см. ниже).
- [emb/structured_log_fluent/](emb/structured_log_fluent/) — Fluent-скин просмотрщика логов (см. ниже).
- [emb/structured_log_cupertino/](emb/structured_log_cupertino/) — Cupertino-скин просмотрщика логов (см. ниже).
- [emb/structured_log_http/](emb/structured_log_http/) — клиентский HTTP-sender логов (см. ниже).
- [backend/structured_log_server/](backend/structured_log_server/) — сервер логирования (см. ниже).
- [frontend/](frontend/) — пока пусто; здесь появится `structured_log_admin_client`.
- [packages/](packages/) — пока пусто; резерв под пакеты вне категорий `emb`/`backend`/`frontend`.
- [melos.yaml](melos.yaml) — манифест workspace и общие скрипты (analyze/format/test/lint/build).
- [pubspec.yaml](pubspec.yaml) — корневой pubspec workspace (`publish_to: none`, не публикуется); нужен
  только для того, чтобы `dart run melos <cmd>` резолвил `melos` как dev-зависимость — сам по себе
  не является пакетом workspace и не перечислен в `packages:` в `melos.yaml`.
- [openspec/](openspec/) — артефакты OpenSpec (proposal/design/specs/tasks) для change-заявок.
- [docs/](docs/) — сквозная (не per-package) документация дизайна: сейчас описывает систему
  `structured_log_server`/`structured_log_http`/`structured_log_admin_client`, спроектированную в
  [openspec/changes/add-structured-log-server/](openspec/changes/add-structured-log-server/) —
  читаемое по темам изложение поверх `design.md`/`specs/*.md`, а не замена им (при расхождении
  приоритет у OpenSpec-артефактов). Билингвальные пары файлов (`*.md`/`*.ru.md`), по той же
  конвенции, что `README.md`/`README.ru.md` и `emb/structured_log/doc/ARCHITECTURE.md`/`.ru.md`. См.
  [docs/README.md](docs/README.md) для оглавления.
- [.github/workflows/ci.yml](.github/workflows/ci.yml) — CI.
- [LICENSE](LICENSE) — лицензия репозитория; копия лежит также внутри `emb/structured_log/`
  (и будет копироваться в каждый новый пакет), так как `dart pub publish` пакует только
  содержимое директории пакета.

Внутри [emb/structured_log/](emb/structured_log/):

- [emb/structured_log/lib/structured_log.dart](emb/structured_log/lib/structured_log.dart) — публичный barrel-файл экспорта.
- [emb/structured_log/lib/src/logger.dart](emb/structured_log/lib/src/logger.dart) — `BoundLogger`, `LogLevel`, `getLogger()`.
- [emb/structured_log/lib/src/configuration.dart](emb/structured_log/lib/src/configuration.dart) — глобальный синглтон `StructlogConfiguration`.
- [emb/structured_log/lib/src/sink.dart](emb/structured_log/lib/src/sink.dart) — `LogSink`, мультивывод с независимой фильтрацией по уровню/категории и runtime-переключением.
- [emb/structured_log/lib/src/correlation.dart](emb/structured_log/lib/src/correlation.dart) — `LogCorrelation`, типизированные id (session/request/connection/tool-call/message/operation) для `BoundLogger.withCorrelation()`.
- [emb/structured_log/lib/src/processors.dart](emb/structured_log/lib/src/processors.dart) — процессоры, трансформирующие запись лога.
- [emb/structured_log/lib/src/formatters.dart](emb/structured_log/lib/src/formatters.dart) — функции вывода (консоль, файл, ротация файлов) — синхронные.
- [emb/structured_log/lib/src/async_file_output.dart](emb/structured_log/lib/src/async_file_output.dart) — `AsyncFileOutput`/`AsyncRotatingFileOutput`, неблокирующие аналоги файлового вывода с сериализованной очередью записи.
- [emb/structured_log/test/structlog_test.dart](emb/structured_log/test/structlog_test.dart) — модульные тесты по компонентам.
- [emb/structured_log/test/integration_test.dart](emb/structured_log/test/integration_test.dart) — интеграционные тесты, проверяющие пакет как целую систему на реальных файлах.
- [emb/structured_log/example/main.dart](emb/structured_log/example/main.dart) — рабочий пример использования.
- [emb/structured_log/doc/ARCHITECTURE.md](emb/structured_log/doc/ARCHITECTURE.md) / [emb/structured_log/doc/ARCHITECTURE.ru.md](emb/structured_log/doc/ARCHITECTURE.ru.md) — внутренний дизайн для контрибьюторов с mermaid-диаграммами (жизненный цикл лог-вызова, мульти-синк роутинг).

Внутри [emb/structured_log_flutter/](emb/structured_log_flutter/):

- [emb/structured_log_flutter/lib/structured_log_flutter.dart](emb/structured_log_flutter/lib/structured_log_flutter.dart) — barrel-файл экспорта.
- [emb/structured_log_flutter/lib/src/log_buffer.dart](emb/structured_log_flutter/lib/src/log_buffer.dart) — `LogBuffer`: кольцевой буфер, `capture()` подключается как `OutputFunction`/`LogSink.output`, отдаёт записи как `ValueListenable`.
- [emb/structured_log_flutter/lib/src/log_viewer_controller.dart](emb/structured_log_flutter/lib/src/log_viewer_controller.dart) — `LogViewerController` (`ChangeNotifier`): фильтры по уровню/категории/поиску, пауза, `clear()`; плюс публичная `logLevelOf()`.
- [emb/structured_log_flutter/lib/src/log_level_colors.dart](emb/structured_log_flutter/lib/src/log_level_colors.dart) — `logLevelColor()`: единственный источник цветов `LogLevel`, общий для всех скинов (Material/Fluent/Cupertino); живёт здесь, а не в конкретном скине, т.к. `Color`/`Brightness` не привязаны ни к одной дизайн-системе — извлечено из `structured_log_material`, когда появился третий скин (`structured_log_cupertino`), см. `design.md` соответствующей change.
- [emb/structured_log_flutter/test/](emb/structured_log_flutter/test/) — тесты (`flutter test`) на `LogBuffer`, `LogViewerController` и `logLevelColor()`.

Внутри [emb/structured_log_material/](emb/structured_log_material/):

- [emb/structured_log_material/lib/structured_log_material.dart](emb/structured_log_material/lib/structured_log_material.dart) — barrel-файл экспорта; реэкспортирует `logLevelColor()` из `structured_log_flutter` (собственной копии палитры у пакета больше нет).
- [emb/structured_log_material/lib/src/material_log_viewer.dart](emb/structured_log_material/lib/src/material_log_viewer.dart) — `MaterialLogViewer`: встраиваемый виджет без своей хромы (тулбар поиска/паузы/очистки, чипы категории и уровня, список); ниже брейкпоинта master-detail — список + модальный `LogEntryDetailSheet` по тапу, на и выше него — список и немодальная `LogEntryDetailPanel` рядом.
- [emb/structured_log_material/lib/src/material_log_viewer_page.dart](emb/structured_log_material/lib/src/material_log_viewer_page.dart) — `MaterialLogViewerPage`: тонкая обёртка `Scaffold`/`AppBar` (заголовок «Logs») вокруг `MaterialLogViewer` для полноэкранного сценария.
- [emb/structured_log_material/lib/src/log_category_chips.dart](emb/structured_log_material/lib/src/log_category_chips.dart) — `LogCategoryChips`: ряд `ChoiceChip` фильтра по `category`, скрывается при <2 категориях.
- [emb/structured_log_material/lib/src/log_entry_tile.dart](emb/structured_log_material/lib/src/log_entry_tile.dart) — `LogEntryTile`: строка списка (уровень/время/event/category); `selected` подсвечивает запись, показанную в `LogEntryDetailPanel`.
- [emb/structured_log_material/lib/src/log_entry_detail_sheet.dart](emb/structured_log_material/lib/src/log_entry_detail_sheet.dart) — `LogEntryDetailSheet`: модальный bottom sheet с полным контекстом записи и копированием (узкие экраны).
- [emb/structured_log_material/lib/src/log_entry_detail_panel.dart](emb/structured_log_material/lib/src/log_entry_detail_panel.dart) — `LogEntryDetailPanel`: тот же контент, что в `LogEntryDetailSheet`, но немодальной панелью для master-detail split (широкие экраны).
- [emb/structured_log_material/lib/src/log_viewer_empty_state.dart](emb/structured_log_material/lib/src/log_viewer_empty_state.dart) — `LogViewerEmptyState`: «логов ещё нет» / «нет по фильтру».
- [emb/structured_log_material/test/](emb/structured_log_material/test/) — виджет-тесты (`flutter test`).
- [emb/structured_log_material/example/](emb/structured_log_material/example/) — полноценное Flutter-приложение (`structured_log_material_example` в `melos.yaml`), запускается через `flutter run -d chrome` (или `-d web-server`) из этой директории; поддерживает web; демонстрирует и `MaterialLogViewerPage`, и встроенный `MaterialLogViewer` в боковой панели.

Внутри [emb/structured_log_fluent/](emb/structured_log_fluent/):

- [emb/structured_log_fluent/lib/structured_log_fluent.dart](emb/structured_log_fluent/lib/structured_log_fluent.dart) — barrel-файл экспорта; реэкспортирует `logLevelColor()` из `structured_log_flutter`.
- [emb/structured_log_fluent/lib/src/fluent_log_viewer.dart](emb/structured_log_fluent/lib/src/fluent_log_viewer.dart) — `FluentLogViewer`: встраиваемый виджет без своей хромы — master-detail split view (список слева, панель деталей справа), тулбар с поиском/`LogCategoryComboBox`/уровнем/паузой/очисткой. Адаптивен под собственную ширину (не окна): ниже брейкпоинта тулбар переносится на вторую строку, а master-detail сворачивается в список с открытием деталей по тапу и кнопкой «назад».
- [emb/structured_log_fluent/lib/src/fluent_log_viewer_page.dart](emb/structured_log_fluent/lib/src/fluent_log_viewer_page.dart) — `FluentLogViewerPage`: тонкая обёртка `ScaffoldPage` (заголовок «Logs», back-кнопка при пуше) вокруг `FluentLogViewer` для полноэкранного сценария.
- [emb/structured_log_fluent/lib/src/log_category_combo_box.dart](emb/structured_log_fluent/lib/src/log_category_combo_box.dart) — `LogCategoryComboBox`: `ComboBox`-фильтр по `category`, скрывается при <2 категориях.
- [emb/structured_log_fluent/lib/src/log_entry_tile.dart](emb/structured_log_fluent/lib/src/log_entry_tile.dart) — `LogEntryTile`: строка списка (бейдж уровня/время/event/category), hover- и accent-подсветка выбора через `HoverButton`.
- [emb/structured_log_fluent/lib/src/log_entry_detail_pane.dart](emb/structured_log_fluent/lib/src/log_entry_detail_pane.dart) — `LogEntryDetailPane`: панель деталей (не модальная) с полным контекстом записи и копированием.
- [emb/structured_log_fluent/lib/src/log_viewer_empty_state.dart](emb/structured_log_fluent/lib/src/log_viewer_empty_state.dart) — `LogViewerEmptyState`: «No logs yet» / «No results found».
- [emb/structured_log_fluent/lib/src/log_level_colors.dart](emb/structured_log_fluent/lib/src/log_level_colors.dart) — только `logLevelAbbreviation()` (короткий бейдж уровня); `logLevelColor()` теперь общий, приезжает из `structured_log_flutter`.
- [emb/structured_log_fluent/test/](emb/structured_log_fluent/test/) — виджет-тесты (`flutter test`); поведенческие тесты (`fluent_log_viewer_test.dart`) пампят `FluentLogViewer` напрямую без `ScaffoldPage`/`Navigator` на широком вьюпорте (1200×800 — дефолтный 800×600 слишком узкий), `fluent_log_viewer_responsive_test.dart` — брейкпоинты на явно заданной ширине через `SizedBox`, `fluent_log_viewer_page_test.dart` — только специфика страницы (заголовок/back-кнопка); скоуп-хелперы `_inList`/`_inDetailPane` (список и панель деталей видны одновременно, `find.text(event)` иначе находит дубликаты).
- [emb/structured_log_fluent/example/](emb/structured_log_fluent/example/) — полноценное Flutter-приложение (`structured_log_fluent_example` в `melos.yaml`), запускается через `flutter run -d chrome` из этой директории; поддерживает web; демонстрирует и `FluentLogViewerPage`, и встроенный `FluentLogViewer` в боковой панели (`Expanded`, не фиксированная ширина — иначе при сужении окна `Row` переполняется).
- `fluent_ui: ^4.16.1` — обычный диапазон, не точный пин. До 2026-09 было зафиксировано точной версией `4.15.1`, т.к. `4.16.1` не компилировалась с Flutter SDK, который тогда был в проекте (`3.41.7`) — рассинхрон API `fluent_ui`/Flutter framework (`RawTooltip.ignorePointer`, `ReorderableListView.builder.onReorderItem`, тип `ScrollCacheExtent`; `flutter analyze` это не ловит, только `flutter test`/`flutter build`). Причина оказалась не в `fluent_ui`, а в устаревшем локальном `stable`-снепшоте FVM в этом репозитории: `fluent_ui 4.16.0` уже требовал Flutter `3.44.0+` («refactor: Flutter 3.44.0 support» в его CHANGELOG), но его собственный `environment.flutter` констрейнт (`>=3.32.0`) этого не отражал. После обновления `.fvm/fvm_config.json` на `3.44.9` (см. ниже) пакет компилируется и все тесты проходят — диапазон снят.

Внутри [emb/structured_log_cupertino/](emb/structured_log_cupertino/):

- [emb/structured_log_cupertino/lib/structured_log_cupertino.dart](emb/structured_log_cupertino/lib/structured_log_cupertino.dart) — barrel-файл экспорта; реэкспортирует `logLevelColor()` из `structured_log_flutter`.
- [emb/structured_log_cupertino/lib/src/cupertino_log_viewer.dart](emb/structured_log_cupertino/lib/src/cupertino_log_viewer.dart) — `CupertinoLogViewer`: встраиваемый виджет без своей хромы — тулбар (`CupertinoSearchTextField`, пауза/очистка), `LogCategoryFilterBar`, `CupertinoSlidingSegmentedControl` уровня, список. Адаптивен под собственную ширину: ниже брейкпоинта master-detail — список, тап пушит `LogEntryDetailPanel` отдельным экраном через `CupertinoPageRoute` (стандартный iOS-паттерн, как в Почте/Настройках на iPhone); на и выше него — список и немодальная `LogEntryDetailPanel` рядом (как на iPad).
- [emb/structured_log_cupertino/lib/src/cupertino_log_viewer_page.dart](emb/structured_log_cupertino/lib/src/cupertino_log_viewer_page.dart) — `CupertinoLogViewerPage`: тонкая обёртка `CupertinoPageScaffold` (заголовок «Logs», back-кнопка при пуше — штатная для `CupertinoNavigationBar`) вокруг `CupertinoLogViewer`.
- [emb/structured_log_cupertino/lib/src/log_category_filter_bar.dart](emb/structured_log_cupertino/lib/src/log_category_filter_bar.dart) — `LogCategoryFilterBar`: горизонтально прокручиваемый ряд pill-кнопок фильтра по `category` (не `CupertinoSlidingSegmentedControl` — тот годится только для маленького фиксированного набора опций, а категории динамические), скрывается при <2 категориях.
- [emb/structured_log_cupertino/lib/src/log_entry_tile.dart](emb/structured_log_cupertino/lib/src/log_entry_tile.dart) — `LogEntryTile`: строка списка (точка уровня/время/event/category); `showsDisclosureIndicator` — шеврон вправо на узких экранах (переход на новый экран), `selected` — подсветка на широких (master-detail).
- [emb/structured_log_cupertino/lib/src/log_entry_detail_panel.dart](emb/structured_log_cupertino/lib/src/log_entry_detail_panel.dart) — `LogEntryDetailPanel`: немодальный контент деталей записи с копированием — используется и в master-detail split, и внутри `CupertinoPageScaffold` при пуше на узких экранах (никакого отдельного «sheet»-варианта, в отличие от `structured_log_material`, — на iOS паттерн детали записи это pushed-экран, а не bottom sheet).
- [emb/structured_log_cupertino/lib/src/log_viewer_empty_state.dart](emb/structured_log_cupertino/lib/src/log_viewer_empty_state.dart) — `LogViewerEmptyState`: «No logs yet» / «No logs match the current filter».
- `CupertinoSlidingSegmentedControl`'s type parameter должен быть non-nullable (`bound Object`) — фильтр уровня (включая `null` = «All») закодирован как индекс в списке опций, а не сам `LogLevel?` напрямую.
- [emb/structured_log_cupertino/test/](emb/structured_log_cupertino/test/) — виджет-тесты (`flutter test`), структура и приёмы тестирования как у `structured_log_fluent`/`structured_log_material` (поведенческие тесты на явно заданной узкой ширине, брейкпоинты — на явно заданной широкой, отдельный тест для page-обёртки).
- [emb/structured_log_cupertino/example/](emb/structured_log_cupertino/example/) — полноценное Flutter-приложение (`structured_log_cupertino_example` в `melos.yaml`), запускается через `flutter run -d chrome` из этой директории; поддерживает web; демонстрирует и `CupertinoLogViewerPage`, и встроенный `CupertinoLogViewer` в боковой панели.
- `cupertino_icons` — обычная зависимость (иконки `CupertinoIcons` не бандлятся во Flutter SDK сами по себе); `uses-material-design: false` — пакет не тянет Material-иконки/шрифты.

Внутри [emb/structured_log_http/](emb/structured_log_http/) (скаффолдинг, Этап 0 — публичный API пока пуст):

- [emb/structured_log_http/lib/structured_log_http.dart](emb/structured_log_http/lib/structured_log_http.dart) — barrel-файл экспорта.
- `lib/src/http_output.dart` (раздел 9 `tasks.md`) — `HttpLogOutput` по паттерну `_SerializedAsyncOutput`/`AsyncFileOutput` из `structured_log` (сериализованная очередь, `catchError` на каждом шаге, публичный `flushed`), плюс батчинг по размеру/таймауту и retry с backoff на сетевых ошибках/5xx (не на 4xx).
- Зависимость — только `structured_log` (чистый Dart, без `dio`/`http`; `dart:io`'s `HttpClient`, как и в `async_file_output.dart` самого `structured_log`).

Внутри [backend/structured_log_server/](backend/structured_log_server/) (скаффолдинг, Этап 0 — публичный API пока пуст, файловая раскладка внутри фичи намеренно не зафиксирована заранее, decision 32 `design.md`):

- [backend/structured_log_server/lib/structured_log_server.dart](backend/structured_log_server/lib/structured_log_server.dart) — barrel-файл экспорта.
- `lib/src/` — по фиче (`auth/`, `users/`, `projects/`, `logs/`, `live_stream/`, `audit/`, ...), плюс `shared`/`common`-слой для сквозных таблиц хранения (`drift`, раздел 2 `tasks.md`) и HTTP-инфраструктуры (`shelf`/`shelf_router`, раздел 6).
- `bin/` — CLI entrypoint (`bin/server.dart`, раздел 8 `tasks.md`), пока не создан.
- Кодогенерация: `drift_dev`/`freezed`/`json_serializable`/`shelf_router_generator` через `build_runner` — `dart run melos run generate` (скоуп `structured_log_server`) или `dart run build_runner build --delete-conflicting-outputs` из директории пакета; `*.g.dart`/`*.freezed.dart` — в `.gitignore` пакета, не коммитятся.
- HTTP-слой: ограничение частоты (`rate_limit_middleware.dart`) стоит в `Pipeline` **до** аутентификации — отклонённый по адресу запрос не должен стоить серверу даже разбора тела; субъектная половина ограничителя вызывается из хендлера (`request.rateLimitAttempt`), потому что субъект известен только ему. Аутентификация — один резолвящий middleware в общем `Pipeline` (`principal_middleware.dart`), а не обёртка на маршруте; хендлер объявляет требуемого принципала сам (`request.requireUser()`/`requireProject()`), и это обязано быть первой строкой — до парсинга path-параметров и любого обращения к БД, иначе 404 о несуществующей строке утекает неаутентифицированному вызывающему. Маршруты задаются аннотациями `@Route.<verb>` на методах классов `*Routes` и собираются `shelf_router_generator`; `buildHandler` только монтирует сгенерированные роутеры. Новый маршрут обязан появиться в таблице `test/http/route_auth_matrix_test.dart` — иначе тест падает.
- `publish_to: none` — самостоятельный сервис, а не библиотека для `pub.dev`.

## Команды

Запускаются через `melos run <script>` из корня репозитория (см. [melos.yaml](melos.yaml)) —
скрипты, кроме `clean`, определены через `exec:`/`steps:` и выполняются в директории каждого
пакета workspace. Если глобально активированный `melos` недоступен/сломан (например, конфликт
версии Dart SDK со снапшотом бинаря), используйте `dart run melos <cmd>` — корневой
[pubspec.yaml](pubspec.yaml) как раз для этого держит `melos` в dev-зависимостях:

```bash
dart run melos bootstrap
dart run melos run analyze
dart run melos run test
dart run melos run lint
```

Для прямых вызовов `dart` нужно сначала зайти в директорию пакета:

```bash
cd emb/structured_log

dart analyze
dart format .
dart format --set-exit-if-changed .   # format:check
dart test
dart test --coverage=coverage
dart run example/main.dart
```

`melos run lint` запускает analyze + format:check вместе; `melos run build` — `pub get` + analyze;
`melos run example` — пример конкретно для `structured_log`.

## Соглашения

- Публичный API `structured_log` экспортируется только через [emb/structured_log/lib/structured_log.dart](emb/structured_log/lib/structured_log.dart); новые публичные символы добавлять туда же.
- `BoundLogger.bind()` / `unbind()` иммутабельны — всегда возвращают новый экземпляр, никогда не мутируют `_context` на месте.
- Процессоры имеют тип `Map<String, dynamic>? Function(Map<String, dynamic> entry)`; возврат `null` отбрасывает запись. Новые процессоры должны быть чистыми функциями и не зависеть от порядка выполнения, если это не документировано отдельно.
- `StructlogConfiguration` — глобальное изменяемое состояние (`_current`); тесты, вызывающие `configure()`, обязаны делать `reset()` в `tearDown`, чтобы не влиять на другие тесты.
- Никаких сторонних runtime-зависимостей у `structured_log` — сохранять это, если явно не попросили иначе. Flutter-пакеты (`structured_log_flutter`/`structured_log_material`/`structured_log_fluent`/`structured_log_cupertino`) этому ограничению не подчиняются, но `structured_log_flutter` сам не должен зависеть от конкретной дизайн-системы (Material/Cupertino/Fluent) — см. design.md в [openspec/changes/add-structured-log-flutter/](openspec/changes/add-structured-log-flutter/).
- Форматирование должно строго соответствовать существующему (`dart format .` перед завершением любого изменения).
- Артефакты OpenSpec ([openspec/changes/](openspec/changes/)) пишутся на русском языке — кроме ключевых слов
  и идентификаторов (заголовки секций типа `## Why`/`## What Changes`, имена пакетов/капабилити,
  имена символов кода, флаги команд и т.п., которые остаются как есть, не переводятся).

## Коммиты и версионирование

- Сообщения коммитов пишутся в формате [Conventional Commits](https://www.conventionalcommits.org/)
  (`feat:`, `fix:`, `docs:`, `chore:`, `refactor:`, `perf:`, `test:`, `build:`, `ci:`, `revert:`;
  ломающее изменение — `!` после типа или футер `BREAKING CHANGE:`). Это нужно, чтобы
  `melos version` мог автоматически определять нужный semver-бамп по истории коммитов.
- `melos version` ищет точку отсчёта по git-тегу вида `<package>-v<version>`
  (например, `structured_log-v0.2.0-dev.1`) и версионирует только коммиты после него —
  без такого тега или без Conventional Commits в истории он не находит, что версионировать.
- `melos version -V <package>:<major|patch|minor|build|exactVersion>` — ручной бамп версии.
  **Важно:** флаги `--no-git-commit-version`/`--no-git-tag-version` НЕ делают команду
  dry-run — файлы (`pubspec.yaml`, `CHANGELOG.md`) переписываются на диске в любом случае.
- **`CHANGELOG.md` вручную не редактировать никогда** — ни для добавления записей о
  новой фиче/фиксе, ни для «уборки» после `melos version` (даже если он переписал файл
  в своём собственном формате поверх предыдущего содержимого). Версию и changelog меняет
  только `melos version` — это осознанное решение мейнтейнера, не пробел в процессе.
- Каждый пакет workspace версионируется независимо — своя линия git-тегов, свой `CHANGELOG.md`.

## CI

[.github/workflows/ci.yml](.github/workflows/ci.yml) запускается на push/PR
в `master`/`develop` и на `workflow_dispatch`, две джобы:

- `test` — для `structured_log`: `dart format --set-exit-if-changed`, `dart analyze`,
  `dart test`, `dart run example/main.dart` — на `ubuntu-latest`/`macos-latest`/`windows-latest`
  (важно именно на всех трёх, т.к. `async_file_output.dart` и ротация делают реальные
  rename/delete/exists на файловой системе, а её поведение отличается между POSIX и Windows).
  Использует `dart-lang/setup-dart` (канал `stable`), а не FVM/Flutter — `structured_log`
  не зависит от Flutter.
- `server` — для `backend/structured_log_server/`: `dart pub get`, `build_runner`,
  `dart format --set-exit-if-changed`, `dart analyze`, `dart test
  --exclude-tags integration`, затем отдельным шагом `dart test --tags
  integration` (поднимает `bin/server.dart` процессом; тег объявлен в
  `dart_test.yaml`, но не исключён — разделение нужно только чтобы в логе
  было видно, какой из двух прогонов упал) — только
  `ubuntu-latest` (сервис самохостится на Linux, ОС-чувствительной ротации
  файлов у него нет). `dart-lang/setup-dart` (канал `stable`), без FVM.
  Кодогенерация **обязана** идти до `analyze`/`test` — без неё пакет не
  компилируется (`*.g.dart` не коммитятся). `melos bootstrap` в CI не
  используется (`sdkPath` в `melos.yaml` указывает на FVM-SDK, которого в CI
  нет) — вместо него джоба сама пишет `pubspec_overrides.yaml` с путём на
  `emb/structured_log`, иначе pub взял бы опубликованную версию и ломающее
  изменение в core-пакете в том же PR прошло бы незамеченным.
- `http-sender` — для `emb/structured_log_http/`: `dart pub get`,
  `dart format --set-exit-if-changed`, `dart analyze`, `dart test` — отдельной
  джобой, а не матричной записью рядом с сервером: пакет чистый Dart без
  кодогенерации, и матрица тянула бы за собой шаг `build_runner` впустую.
  Как и джоба сервера, сама пишет `pubspec_overrides.yaml` на
  `emb/structured_log`.
- `flutter` — для Flutter-пакетов (`structured_log_flutter`, `structured_log_material`
  (+`example/`), `structured_log_fluent` (+`example/`), `structured_log_cupertino`
  (+`example/`)), по одному матричному прогону на пакет:
  `flutter pub get`, `dart format --set-exit-if-changed`, `flutter analyze`, `flutter test`.
  Только `ubuntu-latest` — этим пакетам не нужна ОС-чувствительная проверка ротации файлов.
  Использует `subosito/flutter-action`, канал `stable`.

## Перед завершением изменения

1. `dart analyze` — не должно быть замечаний.
2. `dart test` — все тесты должны проходить.
3. `dart format --set-exit-if-changed .` — код должен быть отформатирован.
4. При изменении публичного поведения пакета обновлять его `README.md`/`README.ru.md`
   ([emb/structured_log/](emb/structured_log/README.md), [emb/structured_log_flutter/](emb/structured_log_flutter/README.md),
   [emb/structured_log_material/](emb/structured_log_material/README.md), [emb/structured_log_fluent/](emb/structured_log_fluent/README.md),
   [emb/structured_log_cupertino/](emb/structured_log_cupertino/README.md))
   — но не `CHANGELOG.md` (см. «Коммиты и версионирование»).
5. CI ([.github/workflows/ci.yml](.github/workflows/ci.yml)) должен быть зелёным на всех джобах.
