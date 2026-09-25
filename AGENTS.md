# AGENTS.md

Инструкции для AI-агентов, работающих в этом репозитории.

## Проект

Репозиторий — multi-package workspace на Melos + FVM, пакеты сгруппированы по категориям
верхнего уровня (каждый пакет — директория `<категория>/<name>/`, перечисленная по полному
пути в [melos.yaml](melos.yaml)): [emb/](emb/) — встраиваемые в чужое приложение библиотеки
(`structured_log`, скины просмотрщика логов, `structured_log_http`), [backend/](backend/) —
самостоятельные серверные приложения (`structured_log_server`), `frontend/` —
самостоятельные клиентские приложения с UI (`structured_log_admin_client`), `packages/` —
пакеты, не подпадающие однозначно ни под одну из трёх категорий выше (пока пусто, без записи
в `melos.yaml`). Первоначально раскладка была полностью плоской, без категорий — по образцу
[cherrypick](https://github.com/pese-git/cherrypick) того же автора; категории введены при
добавлении сервера и admin-клиента
([openspec/changes/add-structured-log-server/](openspec/changes/add-structured-log-server/),
decision 23) — с появлением пакетов другой природы (сервис, приложение, а не только встраиваемая
библиотека) плоский список перестал сам по себе сообщать, что чем является.

[.fvmrc](.fvmrc) пинит Flutter SDK для локальной разработки/`melos`-команд явной
версией (`"flutter"`, сейчас `3.47.4`) — не строкой `"stable"`, чтобы версия не
«уезжала» молча при `fvm install`/`fvm use stable` без явного решения
контрибьютора. Отслеживается git'ом именно `.fvmrc`; `.fvm/` целиком в
`.gitignore`, так что лежащий там `fvm_config.json` — производный файл, а не
источник пина. **CI на пин не смотрит**: `.github/workflows/ci.yml` использует
`dart-lang/setup-dart`/`subosito/flutter-action` с каналом `stable` напрямую (без
FVM), так что CI всегда гоняется на актуальном на момент запуска `stable`-релизе.

**Пин нужно держать вплотную к тому, что на CI, и расхождение обнаруживается не
компилятором, а форматтером.** `dart format` меняет раскладку между версиями
Dart, и `--set-exit-if-changed` тогда валит CI на коде, который локально
отформатирован правильно — причём локальный и CI-шный форматтеры переписывают
файл друг за другом по кругу, из-за чего проверить формат локально становится
нечем. Так и случилось 15.09.2026: пин отставал (`3.44.9` против `3.47.4` на CI),
и один файл раздела 14 разошёлся ровно по этой причине. Поднимать пин —
`fvm use <version>` из корня, затем `dart run melos bootstrap` и полный прогон
`analyze`/`format:check`/`test` по **всем** пакетам: обновление Flutter не раз
ломало `fluent_ui` (см. ниже), и `flutter analyze` этого не ловит.

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
  Реализован (раздел 9 `tasks.md`), с билингвальным `README.md`/`README.ru.md`.

Плюс один пакет в `backend/`:

- [backend/structured_log_server/](backend/structured_log_server/) — self-hosted сервер приёма/
  хранения/поиска/живой трансляции логов (`shelf`+`shelf_router`, `drift`/SQLite по умолчанию,
  либо PostgreSQL как выбираемая оператором альтернатива — `--db-backend=postgres`,
  [openspec/changes/add-postgres-backend/](openspec/changes/add-postgres-backend/)). Реализованы
  приём и запрос логов, живой поток (SSE), группы/проекты/секретные ключи, аутентификация и RBAC,
  ограничение частоты, очистка по retention, собственное логирование и аудит (Этап 2), управление
  пользователями — создание/блокировка/удаление, без `email` — команды (группа/участники) и полная
  выдача ролей (`admin` без ограничений; `owner` группы — `owner`/`user` на неё саму и её проекты;
  `subject_type: user`/`team`) (Этап 4, разделы 4.3/5.3/5.6); не реализованы самостоятельная
  регистрация, восстановление пароля и подтверждение email — `tasks.md` в
  [openspec/changes/add-structured-log-server/](openspec/changes/add-structured-log-server/).
  Отдельно от этих этапов — опциональный, по умолчанию выключенный CORS
  (`--cors-allowed-origins`, [openspec/changes/add-server-cors/](openspec/changes/add-server-cors/)).
  `publish_to: none` — самостоятельный сервис, не библиотека для встраивания.

В `frontend/` два пакета — `structured_log_admin_ui` (раздел 23; Этап 2 добавил в кит `AdminTable` и
`AdminDateRangeField`) и `structured_log_admin_client` (разделы 11/12/13/14/22/27 — слой данных,
вход, принудительная и добровольная смена пароля, группы/проекты/секретные ключи, просмотр и поиск
логов, живая лента; разделы 20/32 Этапа 2 — экран аудита; разделы 13.1/13.3a/13.5a/27.1 Этапа 3 —
экран пользователей, блокировка проекта, урезанный UI выдачи роли. Остался 30.3, и он ждёт раздела 18).
В `packages/` — `structured_log_e2e` (сквозные тесты, см. ниже).

`structured_log_flutter`/`structured_log_material`/`structured_log_fluent`/`structured_log_cupertino`
опубликованы на pub.dev (`0.1.0`, стабильный релиз после серии `-dev.N`, `melos version`
прогнан и теги `<package>-v0.1.0` проставлены). Зависимость на `structured_log_flutter` в
`pubspec.yaml` трёх скинов — обычный hosted-констрейнт (`^0.1.0`), путь к нему при локальной
разработке подставляет `melos bootstrap` через `pubspec_overrides.yaml` (генерируется, не
коммитится — см. `.gitignore`). Их `example/` остаются `publish_to: none` — демо-приложения
не публикуются. История и обоснование решений — в
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
- [frontend/structured_log_admin_ui/](frontend/structured_log_admin_ui/) — библиотека UI-компонентов admin-клиента (см. ниже).
- [frontend/structured_log_admin_client/](frontend/structured_log_admin_client/) — admin-клиент (см. ниже).
- [packages/e2e/](packages/e2e/) — `structured_log_e2e`, сквозные тесты через всю систему (см. ниже).
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
  [docs/README.md](docs/README.md) для оглавления. **Два способа пользоваться проектом —
  самостоятельно (`structured_log` и, по желанию, in-app просмотрщик, вообще без сервера) или
  вместе с self-hosted `structured_log_server` — названы прямо в первом абзаце
  [docs/README.md](docs/README.md)/`.ru.md`, а не выводятся из контекста**; внутри `guides/` это
  разделение проведено буквально — [guides/README.md](docs/guides/README.md)/`.ru.md` группируют
  пять руководств в три раздела («Самостоятельно», «Вместе с self-hosted сервером», «Вклад в
  репозиторий»), и [guides/embedding-guide.md](docs/guides/embedding-guide.md) — единственное
  руководство в первой группе — как добавить `structured_log` и, по желанию, in-app просмотрщик
  (`structured_log_flutter` + один из трёх скинов) в собственное приложение вообще без сервера;
  `structured_log_http` там тоже упомянут, но кратко, с отсылкой на `developer-guide.md` за
  деталями серверной стороны. Добавлено, когда выяснилось, что у `emb/`-пакетов не было отдельной
  инструкции по внедрению внутри `docs/` (decision, 22.09.2026) и затем явно усилено по прямому
  запросу — донести дуальность «сам по себе / вместе с сервером» лаконично на главной странице
  сайта и полно в разделах документации (decision, 22.09.2026); соответствующие разделы
  `developer-guide.md`/`.ru.md` теперь ссылаются на `embedding-guide.md`, а не дублируют
  установку/quick start каждого пакета.
- [site/](site/) — сайт проекта на Astro + Starlight, билингвальный (English/Русский):
  просматриваемая, с поиском версия [docs/](docs/) плюс страница на каждый пакет
  [emb/](emb/) (`/packages/<пакет>/` — установка/quick start/API из его README, раздел
  добавлен, когда выяснилось, что у встраиваемых библиотек на сайте не было вообще никакой
  документации по использованию). Главная страница (`index.mdx`/`ru/index.mdx`) прямо на виду
  отражает ту же дуальность, что и `docs/README.md`: вступительный абзац называет оба режима, а
  «Quick start» — это `<Tabs>` (Starlight) с двумя вкладками, «Standalone, no server» и «With the
  self-hosted server», вместо одного линейного пути через сервер; карточки пакетов ниже —
  два `<CardGrid>`, один на каждый режим, а не одна общая сетка. Самостоятельный npm-проект вне
  Melos workspace, не перечислен в `melos.yaml`. Контент **генерируется** скриптом
  ([site/scripts/migrate_docs.py](site/scripts/migrate_docs.py)) из `docs/**/*.md`/`*.ru.md`
  и `emb/<пакет>/README(.ru).md`, а не пишется вручную — правки вносятся в источник, затем
  скрипт перегенерирует `site/src/content/docs/`. Ссылки, ведущие за пределы переносимого
  источника (на `openspec/`, исходники других пакетов, `AGENTS.md`, example-приложение),
  скрипт переписывает на `github.com/pese-git/structured_log`. Главная страница
  (`index.mdx`/`ru/index.mdx`), оглавление пакетов (`packages/index.md`/`ru/packages/index.md`)
  и `astro.config.mjs` — вручную, скриптом не трогаются (`PROTECTED` в самом скрипте — и
  `site/.gitignore`'s исключения для `src/content/docs/` держатся в синхроне с этим списком
  вручную, не выводятся автоматически). Mermaid-диаграммы архитектурных страниц рендерятся на
  клиенте (`astro-mermaid`), без build-time Chromium. См. [site/README.md](site/README.md).
- [deploy/](deploy/) — самостоятельное развёртывание через docker-compose: сервер и admin-клиент за одним
  nginx (см. ниже).
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

Внутри [emb/structured_log_http/](emb/structured_log_http/):

- [emb/structured_log_http/lib/structured_log_http.dart](emb/structured_log_http/lib/structured_log_http.dart) — barrel-файл экспорта.
- [emb/structured_log_http/lib/src/http_output.dart](emb/structured_log_http/lib/src/http_output.dart) — `HttpLogOutput`: батчинг по размеру/таймауту, retry с backoff на сетевых ошибках/таймаутах/5xx (на 4xx — нет, кроме `408`/`429`), ограниченный буфер с вытеснением самых старых, публичный `flushed`. **Все неотправленные записи лежат в одной очереди, из которой насос забирает по `batchSize`** — первая версия выстраивала батчи цепочкой futures, и лимит буфера тогда не ограничивал память (см. 9.4 в `tasks.md`).
- Транспорт — `dart:io`'s `HttpClient`, зависимость только `structured_log` (без `dio`/`http`). Шов `BatchSender` позволяет тестировать батчинг/retry/вытеснение без сокета; отдельная группа тестов работает против настоящего `HttpServer`.
- `README.md`/`README.ru.md` — билингвальная пара, как у остальных пакетов.

Внутри [frontend/structured_log_admin_ui/](frontend/structured_log_admin_ui/):

- Библиотека компонентов `structured_log_admin_client` по Atomic Design — `tokens`/`atoms`/`molecules`/`organisms`,
  без `templates`/`pages` (те собирают экран вокруг реальных данных и остаются в клиенте, decision 39).
- Зависимости — **только** `flutter` sdk и `fluent_ui`. Ни `flutter_bloc`/`cherrypick`/`dio`/`fpdart`/`freezed`,
  ни самого `structured_log_admin_client`: направление зависимости одностороннее, и это проверяется
  компилятором, а не соглашением. Намерение продублировано тестом `test/package_boundary_test.dart`.
- `lib/src/tokens/` — значения перенесены из канваса «Structured Log Admin UI» (макеты живут вне
  репозитория, ссылки — в памяти сессии; все 26 артбордов делят один блок `--fl-*`). Палитра уровней
  лога — **своя копия**, не импорт из `structured_log_flutter` (decision 39, тот же принцип, что между
  `structured_log_material` и `structured_log_fluent`). Фон бейджа уровня не таблица, а правило «цвет
  поверх поверхности при alpha 0.16»: оно воспроизводит все четыре значения канваса точно и потому даёт
  согласованные `trace`/`critical`, которых нет ни на одном артборде.
- **Канвас светлый.** Тёмная тема выведена, а не сверена. Узкие состояния дорисованы в задаче 23.9 —
  артборды `GroupsNarrow.dc.html` и `LogBrowserNarrow.dc.html`.
- **`AdminTable` (единственный потребитель — `AuditPage`) ниже своего порога скроллится вбок, а не
  переполняется.** У `AuditLog.dc.html` нет узкой раскладки (решение пользователя, `AdminTable` этим не
  переопределяется), а четыре фиксированные колонки экрана аудита (128+150+196+210) шире, чем оставляет
  узкий (`< masterDetail`) клиент с уже свёрнутым рельсом — `Row` в этом случае переполняется (`RenderFlex
  overflowed`), потому что `SizedBox` фиксированной колонки не уступает место. Порог — сумма фиксированных
  колонок, зазоров между ними, пола под гибкую колонку (160, чтобы не схлопывалась до нуля вместе со
  скроллом) и собственных отступов строки; ниже него таблица кладётся в `SingleChildScrollView` по
  горизонтали на фиксированной ширине-пороге — выравнивание колонок остаётся, просто часть уходит за
  край до прокрутки. Тест на воспроизведение переполнения нужен ровно с шириной сцены `< 700` — виджет-тест
  по умолчанию (800×600) переполнения не покажет.
- Брейкпоинты — `AdminBreakpoints` (`navRail = 900`, `masterDetail = 700`) и меряются **по собственной
  ширине виджета** через `LayoutBuilder`, а не по ширине окна: панель внутри сплита не становится
  широкой оттого, что широко окно. Тот же принцип, что в скинах `emb/`. Практическое следствие для
  тестов: дефолтный вьюпорт виджет-теста (800×600) **ниже** `navRail`, поэтому тест про подписанный
  nav-pane обязан явно задать ширину — иначе он видит рельс.
- `example/` — web-галерея компонентов (`structured_log_admin_ui_example`), `flutter run -d chrome`.
  В её тестах `pumpAndSettle` неприменим: `AdminLoadingIndicator` крутится вечно, нужен `pump`.
- `publish_to: none` — привязан к эстетике одного клиента, не кит общего назначения.

Внутри [frontend/structured_log_admin_client/](frontend/structured_log_admin_client/):

- Приложение (`publish_to: none`), web-платформа. Готовы слой данных (11), вход (12), управление
  группами/проектами/ключами (13 в объёме Этапа 1), экран логов с живой лентой (14/22) и смена
  пароля — принудительная и из настроек (27.2–27.4).
- **Гейт `must_change_password` — третье состояние сессии**, не разновидность «вышел»: сессия
  исправна и токены на месте, закрыто всё остальное. Перехват в `AuthInterceptor` рядом с 401,
  состояние в `SessionController`, экран выбирает `AuthGate`. Там же важная тонкость: 401 с кодом
  `invalid_grant` **не** обновляет токен — так отвечает `change-password` на неверный текущий
  пароль, и повтор засчитал бы серверу вторую неудачную попытку на пользовательский лимит
  (протухший токен сервер зовёт `unauthorized`).
- Смена пароля рвёт **все остальные** сессии, но не текущую. Сервер отзывает каждый
  refresh-токен учётной записи, кроме предъявленного в `current_refresh_token`; клиент
  всегда присылает свой (`AuthRepositoryImpl` читает его из `TokenStorage` — ни кубит, ни
  форма токена не видят), поэтому его собственная сессия живёт, а `token_version` гасит
  только access-токен, и следующий запрос обновляется штатным путём перехватчика.
  **Отсутствие поля означает отзыв**, а не сохранение: сервер не может определить, чья
  сессия спрашивает, и потому подметает вызывающего вместе с остальными. Галка «Оставить
  другие устройства в системе» на экране настроек шлёт `keep_other_sessions: true`; на
  принудительном экране её нет (`ChangePasswordForm.offerKeepOtherSessions`).
- **Тело `change-password` называет токен, а перехватчик его по дороге меняет — и это
  единственный запрос, которому повтор после 401 вредит.** Тело собирается из того, что
  лежит в `TokenStorage` на момент вызова; если access-токен к этому моменту протух, запрос
  получает 401, `AuthInterceptor` обновляет пару (сервер **ротирует** refresh-токен: старый
  тут же отзывается) и повторяет **исходное** тело — а оно называет уже отозванный токен.
  Сервер честно щадит названный (мёртвый) и подметает живой, лежащий в хранилище: смена
  пароля со своего же экрана выкидывала сессию, ровно ту, которая по контракту обязана
  выжить. Починка — `AuthInterceptor._renameSpentRefreshToken`: перед повтором поле
  `current_refresh_token`, если оно называет только что потраченный токен, переписывается на
  выданный. Сверяется по значению, а не по пути: тело, называющее *чужой* токен, трогать
  нечего. Стерегут два теста, оба мутацией проверены: `test/integration/
  account_settings_integration_test.dart` (экран, поверх мока) и `packages/e2e/test/
  aged_session_test.dart` (настоящий сервер — ротация, которая ломает щадящий токен, его, а
  не мока). Свежая сессия дефекта не показывает вовсе — нужен протухший access-токен, поэтому
  найдено вождением стенда, а не тестом. **Состарить сессию, не ожидая пятнадцати минут:**
  вторая сессия того же аккаунта меняет пароль с `keep_other_sessions: true` —
  `incrementTokenVersion` в `change_password_route.dart` безусловен, а подметание нет, так
  что access-токен первой умирает, а refresh-токен живёт.
- Имя пользователя для экранов берётся из claim `preferred_username` access-токена
  (`shared/auth/access_token_claims.dart`) — `GET /v1/users/me` в Этапе 1 нет. Подпись не
  проверяется и не должна: claim нужен только чтобы подписать экран.
- Квота проекта: «без лимита» уходит **явным `null`**, поэтому у обновления свой DTO без
  `includeIfNull: false` — сервер отличает «не трогать» от «снять лимит» по наличию ключа. Ответ
  `PATCH` не несёт `entry_count`/`total_bytes` (их считает только `GET /v1/projects/{id}`), и экран
  после сохранения оставляет уже показанные счётчики.
- `AdminAppShell.title` — **nullable, и экраны клиента передают `null`**: на артбордах заголовок
  один и стоит в одной строке со своим действием, поэтому его рисует страница, а не оболочка.
- Раскладка: `lib/shared/` (`api`/`auth`/`config`/`di`/`logging`) + `lib/features/<фича>/` с
  `domain`/`application`/`infrastructure`/`presentation`. **Директории заводятся вместе с первым
  файлом**, а не пустыми (decision 32), поэтому `features/` растёт по мере разделов 13/27.
- **Локализация — английский и русский, через `gen-l10n`.** Тексты живут в
  `lib/l10n/app_en.arb` (шаблон: ключ, описание, плейсхолдеры) и `app_ru.arb`; сгенерированные
  `app_localizations*.dart` **коммитятся** (`l10n.yaml`, не synthetic-package), так что CI для них
  ничего не делает. Экран читает текст как `context.l10n.ключ`; код вне `build` (описания ошибок,
  подписи действий) принимает `AppLocalizations l10n` первым параметром — `BuildContext` нигде не
  сохраняется, а кубиты текста не знают вовсе (они отдают коды/типы отказов). Даты — через
  `formatDate`/`formatDayMonth` из `lib/l10n/formatting.dart` (сокращения месяцев берутся из ARB,
  а не из `intl`, чтобы «14 фев 2025» выглядело как на канвасе и не требовало инициализации
  дат `intl`). Язык выбирает `LocaleController` (`shared/l10n/`): пока выбора нет — язык браузера,
  для неизвестного — английский; выбор лежит в `localStorage` (`locale_store_web.dart`, условный
  импорт как у стриминга; вне web — в памяти) и переключается карточкой «Язык» на странице
  настроек аккаунта, а до входа — парой ссылок English / Русский в углу экранов входа и
  принудительной смены пароля (`AuthLanguageSwitch`, без пункта «как в браузере»). Роли и типы областей (`admin`/`owner`/`user`, `global`/`group`/`project`)
  показываются идентификаторами, а не переводом — как на канвасе. Виджеты `structured_log_admin_ui`
  языка не знают: их подписи по умолчанию английские, а экран передаёт свои явно. Новый текст =
  ключ в обоих ARB; `test/l10n/arb_parity_test.dart` краснеет, если у русского ключа нет пары
  (`gen-l10n` в этом случае молча берёт английский). Виджет-тесты хостят экран в
  `localizedApp` из `test/support/localized_app.dart` — по умолчанию русский, потому что
  утверждения написаны против русских строк; интеграционные пины `AdminApp` на русский —
  через `LocaleController(initial: Locale('ru'))`.
- `ApiClient` держит **три** инстанса `dio`, и это главное, что нужно знать до правок: основной с
  перехватчиком аутентификации; клиент обновления **без** перехватчика (refresh, которому ответили
  401 на основном инстансе, вошёл бы обратно в тот же перехватчик); клиент повтора исходного
  запроса. Токен-эндпоинт исключён по пути, а не только по флагу — 401 от него означает неверный
  пароль или израсходованный refresh-токен. Параллельные 401 делят одно обновление.
- `retrofit`-интерфейсы заведены **только под существующие маршруты сервера**; `GET /v1/logs/stream`
  в них отсутствует намеренно (decision 37) — SSE написан вручную поверх того же `dio`
  (`features/log_browser/infrastructure/log_stream_client.dart`, раздел 22). Переподключение с
  backoff живёт там же, а не в презентационном слое: обрыв, простой и `end: token_revoked`
  лечатся новым запросом с `since_id`, и экран о них не узнаёт. Параметры запроса списка
  (сгенерированный `LogsApi`) и подписки (`logQueryParameters()`) — две копии, которые держит
  вместе только `test/features/log_browser/log_query_params_test.dart`.
- **`dio` на web не умеет стримить ответ**, и это не настраивается: браузерный адаптер ставит
  `xhr.responseType = 'arraybuffer'` и отдаёт тело в `onLoad`. Живая подписка поэтому читается
  через `fetch`/`ReadableStream` — подменён только адаптер (`shared/api/streaming/`, условный
  импорт; вне web возвращается `null`). Адаптер стоит на отдельном `ApiClient.streamDio`, и тот
  несёт **тот же объект** `AuthInterceptor`, что основной инстанс: гарантия «одно обновление
  токена в полёте» живёт в экземпляре, два экземпляра её бы сломали. Юнит-тесты это не ловят —
  они на Dart VM с подставным адаптером; ловится только браузером.
- Экран логов — один держатель состояния, `LogFeedBloc`: список, пагинация, подписка и пауза в
  одном объекте, потому что «сменился фильтр» это один переход (сброс страницы + закрытие
  подписки + открытие новой). Список рисуется `reverse: true` — индекс 0 это низ и живой край,
  поэтому ни новая запись снизу, ни подгруженная сверху страница не двигают прокрутку читателя.
- **Три ловушки `testWidgets`, и ни одна не в нашем коде.** Первые две — с `Bloc` (с `Cubit` их нет,
  обе всплыли при переходе в разделе 22): блок, созданный в `setUp`, не обрабатывает события внутри
  виджет-теста — строить его надо в теле теста; и `Bloc.close()` внутри `testWidgets` не завершается
  никогда — в `tearDown` его нельзя ожидать (воспроизводится на двухстрочном блоке). Третья — из
  `test/integration/`: **отмена подписки на `async*`-генератор под фейковыми часами не завершается
  никогда**, поэтому `LogStreamClient`, выходящий из `await for` по `break` после кадра `event: end`,
  в виджет-тесте останавливается там и переподключения не делает. Оборванное соединение (`drop`)
  завершает тот же цикл без отмены и переподключается под фейковыми часами штатно — так что это
  харнесс: в настоящем async переподключаются оба пути.
- **Списки читаются постранично, и «первая страница = всё» — ошибка.** Репозитории групп и проектов
  отдают `CursorPage` (`shared/api/cursor_page.dart`: `items` + `nextCursor`, `hasMore`), а не список:
  сервер режет ответ на 50, и экран, не пошедший по `next_cursor`, молча теряет хвост. Экраны с
  полным списком (`GroupsCubit`, список проектов в `GroupDetailCubit`, `UsersCubit`, `AuditCubit`)
  подгружают кнопкой «Показать ещё»; дашборд просит ровно столько, сколько рисует карточек
  (`DashboardCubit.groupCardCount`/`projectCardCount`); селектор области в логах держит курсор на
  каждый из двух списков (`ScopeOptions.groupsCursor`/`projectsCursor`, событие `moreScopesRequested`).
  Пикеры (`AdminSearchPicker`) ищут на сервере (`?name=`/`?username=`, страница в 20) и, когда совпадений
  больше, дописывают **строку-подсказку** `AdminSearchPickerItem.hint(...)` — обрезанный список иначе
  читается как «других нет». Лента логов не держит больше `maxHeldEntries` записей, пока читатель у
  живого края (обрезка — с дальнего конца, курсор возвращается на самую старую оставшуюся). Виджет-
  тесты фейков этого не ловят — фейк отвечает тем, что у него спросили; ловят `test/integration/`
  (мок в `lib/testing/mock_server.dart` режет страницы как сервер) и `packages/e2e`.
- **`integration_test/` — путь оператора на живом приложении.** Запускается не `flutter test`, а
  `flutter drive --driver=test_driver/integration_test.dart --target=integration_test/user_flow_test.dart
  -d web-server --browser-name=chrome` (нужен запущенный `chromedriver`; **`-d chrome` не годится** —
  тогда браузер поднимается мимо драйвера и результат не возвращается). Смысл в биндинге:
  `IntegrationTestWidgetsFlutterBinding` не подменяет ввод и не глушит HTTP, поэтому тап — это тап по
  координатам, а текст приходит по той же платформенной дорожке, что и с клавиатуры. Сеть при этом
  всё равно мок: **сервер без CORS**, и приложение с порта `flutter run` до API на другом порту не
  доходит вообще (проверено вручную 15.09.2026 — экран говорит «Сервер недоступен»). Мок живёт в
  `lib/testing/`, а не в `test/`: у web-цели корнем компиляции становится `integration_test/`, и
  относительный импорт в `test/` не находится; направление зависимости стережёт
  `test/testing_boundary_test.dart`. Есть и `test_driver/app.dart` — то же приложение с включённым
  driver-расширением, чтобы водить его руками через dart MCP (`flutter run --print-dtd` →
  `connect_dart_tooling_daemon`); именно так был найден дефект ниже.
- **Содержимое `ContentDialog` не пишется голой `Column`.** Диалог отдаёт `content` в **loose**
  `Flexible` — это максимум высоты, а не жёсткая высота, — а `Column` по умолчанию
  `MainAxisSize.max` и забирает её целиком: диалог с одним полем и фразой стоял 876 при экране 900.
  Либо `SingleChildScrollView` (так во всех диалогах `resource_dialogs.dart` и в настройках
  аккаунта — заодно короткое окно прокручивается, а не переполняется), либо
  `mainAxisSize: MainAxisSize.min` (так в `AdminConfirmDialog`). Держит
  `test/features/resources/dialog_layout_test.dart`, меряющий **видимую** коробку: сам
  `ContentDialog` растягивается на всю область и о размере диалога не говорит ничего.
- **Диалог, закрывающий сам себя, обязан делать это один раз.** `GroupsPage`, `GroupDetailPage` и
  `ProjectDetailPage` закрывают свой диалог из `addPostFrameCallback`, когда состояние говорит
  «готово». Билдер выполняется на **каждом** изменении состояния, а создание сущности эмитит дважды —
  результат и перезагрузку списка за ним, — поэтому без флага `closing` в очередь встают два `pop`:
  маршрут ещё смонтирован на анимации выхода, так что `dialogContext.mounted` второй не отсекает, и
  закрывается то, что оказалось сверху. У ключей это стоило единственной копии секрета: ключ создан,
  сервер хранит только хэш, окно с значением закрылось само. Найдено 15.09.2026 вождением браузера;
  **виджет-тест это не ловит** — под фейковыми часами эмиты не переслаиваются, и `flutter test`
  проходил с дефектом. Сторож — браузерный `integration_test/user_flow_test.dart`.
- **`test/integration/` — сквозные тесты клиента поверх мока сетевого слоя**
  ([lib/testing/mock_server.dart](frontend/structured_log_admin_client/lib/testing/mock_server.dart)):
  `MockServer implements HttpClientAdapter`, то есть шов проходит ниже всего клиентского стека —
  настоящие `dio`, перехватчик с обновлением токена, сгенерированные `retrofit`-клиенты, рукописный
  парсер SSE, маппер ошибок и DTO работают против байтов. Мок **с состоянием** и отвечает картами, а
  не DTO клиента: мок, отвечающий моделями самого клиента, не может с ним разойтись в формате
  провода, а именно там жили оба дефекта 15.09.2026. Экранные тесты с подставным репозиторием этот
  слой не проходят и потому его не заменяют. Отдельно лежит `user_flow_test.dart` — путь оператора
  целиком (временный пароль → его смена → группа → проект → ключ → чтение логов → живая лента →
  выход) шагами по порядку, разделяющими одно хранилище токенов. **Тот же путь через настоящий
  сервер написать нельзя:** `TestWidgetsFlutterBinding` принудительно отвечает 400 на любой запрос
  `HttpClient`, так что виджет-тест с реальным сокетом невозможен by design — поэтому e2e через
  процесс сервера (`packages/e2e`) остаётся на уровне репозиториев, а UI-путь живёт здесь, поверх
  мока. Не покрыт браузер — как и в `packages/e2e`.
- `LogEntryDto` разобран вручную: сервер разливает `context` по верхнему уровню ответа, и
  `json_serializable` не умеет «эти ключи мои, остальное сохрани».
- **DI: `cherrypick` 4.x, модули фич — `@module()`, генерируются.** Пять фичевых модулей (`features/<фича>/di/`) —
  абстрактные классы с методами `@provide()`/`@singleton()`; `cherrypick_generator` пишет `$<Модуль>`
  (`*.module.cherrypick.g.dart`, не коммитится, как остальные `*.g.dart`; директива `part` обязана называться
  `<файл>.module.cherrypick.g.dart`). `AppModule` рукописный: ему нужны аргументы конструктора (конфиг, логгер,
  подмены для тестов), а генерируемый класс их не принимает. **Только `@provide()`, не `@instance()`**: `@instance`
  — это `toInstance`, который вычисляется сразу в `builder`, когда соседние биндинги модуля ещё не видны, и
  `Can't resolve dependency` падает при `installModules`, хотя зависимость объявлена. Генератор **не проверяет граф**:
  тип без провайдера проходит `analyze` и сборку и падает `StateError` при первом `resolve` — поэтому
  `test/shared/di/scopes_test.dart` резолвит из каждого скоупа всё, что модуль обещает (мутацией проверено: убрать
  метод — тест красный). Жизненный цикл: `ApiClient implements Disposable` и закрывает свои четыре `Dio` при закрытии
  скоупа; `HomeShell` закрывает свои четыре скоупа в `dispose` (`close<Фича>Scope`), `AuthGate` — `auth` (скоуп
  общий: `HomeShell` открывает его тем же именем, поэтому не закрывает). Включены детекция циклов
  (`enableGlobalCycleDetection` + межскоуповая) и `StructuredLogCherryPickObserver` (сцена/модули/освобождение — debug,
  цикл — error; **запросы и создание экземпляров не пишутся**: контейнер спрашивают постоянно, а печатать
  экземпляр значит печатать `TokenStorage`). Наблюдатель — реализация интерфейса, не наследник
  `SilentCherryPickObserver`: контейнер не зовёт наблюдателя, который им является. `cherrypick_flutter` не
  используется намеренно: его `CherryPickProvider` отдаёт **глобальный** корневой скоуп, а клиент передаёт `Scope`
  явно (`AdminApp(scope: ...)`), так что тесты не делят состояние.
- Кодогенерация: `freezed`/`json_serializable`/`retrofit_generator` через `build_runner` —
  `dart run melos run generate` или из директории пакета; `*.g.dart`/`*.freezed.dart` не коммитятся.
  **`retrofit_generator` — 10.x, не 9.x**: 9.7.0 объявляет `retrofit: ^4.6.0`, но не компилируется с
  4.10 (в enum `Parser` появилось значение, которого нет в его switch) — тот же класс ловушки, что с
  `fluent_ui`/Flutter. 10.x требует `build ^4`, а `freezed` 2.x — `build ^2`, поэтому `freezed` здесь 3.x.
- `environment.sdk` — `^3.9.0`, а не привычный воркспейсу `^3.0.0`: `json_serializable` генерирует
  null-aware elements (`?instance.field`) для `includeIfNull: false` (нужен 3.8), а `cherrypick_generator`
  требует 3.9.
- `analysis_options.yaml` гасит `invalid_annotation_target` — `freezed` ставит `@JsonKey` на параметры
  конструктора, это штатный обходной путь самого `freezed`.

Внутри [backend/structured_log_server/](backend/structured_log_server/) (файловая раскладка внутри фичи намеренно не фиксировалась заранее, decision 32 `design.md`):

- [backend/structured_log_server/lib/structured_log_server.dart](backend/structured_log_server/lib/structured_log_server.dart) — barrel-файл экспорта.
- `lib/src/` — по фиче: `auth/` (токены, пароли, принципал), `rbac/`, `storage/` (`drift`-схема, `LogStore`, `LogFilter`), `ingest/`, `live/` (broadcast живого потока), `retention/` (purge job), `config/`, `logging/`, `http/` (middleware + `routes/`).
- `bin/server.dart` — CLI entrypoint: команды `serve`/`create-admin`, резолвер конфигурации, автосоздание первого администратора, таймер очистки, graceful shutdown по SIGINT/SIGTERM.
- `README.md`/`README.ru.md` — путь от пустой БД до прочитанного лога; команды в нём проверены прогоном против запущенной сборки (10.8 в `tasks.md`).
- Кодогенерация: `drift_dev`/`freezed`/`json_serializable`/`shelf_router_generator` через `build_runner` — `dart run melos run generate` (скоуп `structured_log_server`) или `dart run build_runner build --delete-conflicting-outputs` из директории пакета; `*.g.dart`/`*.freezed.dart` — в `.gitignore` пакета, не коммитятся.
- Периодическая очистка по `retention_days` (`lib/src/retention/purge_job.dart`)
  живёт таймером в `bin/server.dart` и останавливается в shutdown до закрытия БД.
  Удаление — порциями, порция и уменьшение `project_usage` в одной транзакции.
- **Три имени полей записи зарезервированы** — `id`, `project_id`, `received_at`. `POST /v1/logs`
  отклоняет запись, которая их содержит (`reservedEntryFieldNames` в `lib/src/ingest/ingest.dart`),
  поштучно, не роняя батч. Причина в форме ответа: `GET /v1/logs` отдаёт запись как её контекст с
  этими тремя полями поверх, так что прикладное поле с таким именем сохранилось бы в базе и исчезло
  из ответа. Формат ответа менять не стали (решение мейнтейнера), поэтому защита стоит на приёме.
- **Пять списков пагинируются одним контрактом** — `GET /v1/logs`, `/v1/audit-log`, `/v1/users`,
  `/v1/groups`, `/v1/projects` (`log-server-pagination`, change `add-list-pagination`): `limit` (по
  умолчанию 50, предел 200 — большее **приводится** к пределу, а не отклоняется), `cursor` по `id`,
  порядок по убыванию `id`, `next_cursor: null` на последней странице. Разбор — один
  (`http/page_request.dart`, `parsePageRequest`), проба `limit+1` — одна (`storage/page.dart`,
  `pageFromProbe`); недопустимый `limit`/`cursor` — `400`, а не `500`/`assert`. Разбор идёт **после**
  проверки роли: `owner` с плохим `limit` на `/v1/audit-log` получает `403`. У групп и проектов
  видимость вызывающего — **условие SQL** (`rbac/access_check.dart`, `readableScope`), а не фильтр по
  прочитанным строкам: иначе страница «50 строк, из них 3 видимых» пуста по существу, а курсор считался
  бы по чужим строкам. `readableScope` и `canRead` — одно правило, записанное двумя способами;
  `test/http/routes/list_pagination_test.dart` держит их вместе. Списки, ограниченные размером одной
  группы/проекта (команды, участники, ключи, выдачи ролей), **сознательно не пагинируются**; условия
  пересмотра — в `design.md` change. Номеров страниц и `total` нет намеренно: курсорная модель их не даёт.
- **Пароли: bcrypt считается не на изоляте запросов, а правило длины одно.** Одна проверка bcrypt —
  ~130 мс CPU, на изоляте, обслуживающем запросы, это остановка всего сервера, поэтому хендлеры зовут
  `hashPasswordAsync`/`verifyPasswordAsync` (`auth/hashing.dart` → `HashWorkerPool`, воркеры поднимаются
  по требованию до `min(4, ядра − 1)`, `close()` — в shutdown). Синхронные `hashPassword`/`verifyPassword`
  остались только для CLI и bootstrap до старта. **Хэширование — до транзакции, не внутри:** иначе оно
  держит блокировку записи. Вход считает bcrypt всегда, для неизвестного/заблокированного/удалённого —
  против `dummyPasswordHash` (создаётся до `serve`): иначе время ответа выдаёт, какой из случаев это.
  Пароль при *задании* — от 8 символов до 72 **байт** (`requireAcceptablePassword`; библиотека bcrypt
  бросает на длинном, а не обрезает): `400 invalid_request` с `details.reason` `too_short`/`too_long` и
  пределом рядом. Тем же правилом проверяются пароль bootstrap-админа (`ParamSpec.validator` — ошибка
  конфигурации, значение в сообщение не попадает) и `create-admin`. При входе правило **не** применяется.
  Клиент не повторяет числа: `shared/auth/password_rejection.dart` читает предел из ответа, а мок
  (`lib/testing/mock_server.dart`) отвечает по тому же правилу — тест, идущий через мок, видит настоящий отказ.
- **База: `busy_timeout` 5 с и `synchronous=NORMAL` заданы жёстко, версия схемы проверяется при открытии.**
  Сборка отказывается стартовать на базе, записанной более новой схемой (drift без этого открывает её молча).
  Всё это (как и пул читателей ниже) специфично для SQLite-пути (`--db-backend=sqlite`, по умолчанию) —
  у PostgreSQL-пути (`--db-backend=postgres`) своя реализация, см. отдельный пункт ниже.
- **Чтения идут через пул соединений, запись — через одно.** `StructuredLogDatabase.open(path, readPool: N)`
  (`--db-read-pool-size`, по умолчанию 2, `0` — как раньше) поднимает N изолятов только для `SELECT` вне
  транзакции; всё, что пишет или идёт внутри транзакции, остаётся на писателе (`MultiExecutor` drift, нужен WAL).
  Без пула одно соединение — одна очередь на всё: чтение рядом с приёмом стояло за пачками записи (48 мс p50 против
  4 в одиночку), а полнотекстовый поиск без совпадений останавливал и приём. С пулом — 7 мс и 5 мс. Ограничения:
  `tableUpdates` слышит только писателя (там же пишется `projects`, за которым следит `ProjectDirectory`);
  `NativeDatabase.memory()` между изолятами не делится, поэтому пул есть только у файловой базы.
- **Транзакция внутри транзакции — не бесплатна, и приём логов на этом терял половину времени.** drift делает
  вложенный `transaction` в `SAVEPOINT`, а SQLite тогда пишет в поджурнал каждую страницу, которую
  затрагивают запросы. `LogStore.insertBatch` поэтому входит в транзакцию вызывающего и открывает свою
  только если её нет (`StructuredLogDatabase.isInTransaction`; тест закрепляет, что он отвечает, потому что
  опирается на `@internal` drift). Он же пишет пачку одним `batch`, а не `insertReturning` на запись (каждый
  — обмен с изолятом БД), и читает строки обратно по диапазону id от `last_insert_rowid()`: id
  `AUTOINCREMENT`, соединение одно и транзакция его держит, так что чужой вставки между ними быть не может.
  Замер до/после на пачке в 100 записей: 6,7 → 22 тыс. записей/с. Найдено профилем, не догадкой:
  бенчмарк в форме продакшена воспроизвёл 13,8 мс на пачку против 14,2 мс CPU на запрос под нагрузкой.
- **Одновременные `POST /v1/logs` коммитятся вместе (`IngestCoordinator`).** Запрос раньше открывал свою транзакцию
  (begin, чтение usage, вставка, обновление usage, commit — шесть обменов с изолятом БД), и для клиента, шлющего по
  одной записи, эта фиксированная цена *и была* запросом: ~0,65 мс CPU против ~50 мкс на каждую следующую запись
  большой пачки. Теперь запросы, пришедшие пока идёт транзакция, ждут её и уходят в следующую все вместе; **ожидания
  «ради компании» нет** — без нагрузки группа из одного запроса и задержка не растёт. Сохранено: квоты считаются
  строго по порядку прихода внутри транзакции (mutation: без накопления usage тест квоты краснеет), публикуется
  один список в порядке id после commit'а (подписка группы отбрасывает запись с id не выше последнего доставленного).
  Сбой самой транзакции роняет все запросы группы, плохой запрос до неё не доходит (разбор и валидация раньше).
  Предел группы — `maxEntriesPerGroup` (2000), чтобы одна транзакция не держала писателя долго. Замер: одиночные
  записи 2,2 → 3,8 тыс. запросов/с; пачки по 100 при 16 продюсерах 21,9 → 29,2 тыс. записей/с; приём рядом с
  чтением 12,7 → 18,1 тыс. (чтение 1146 → 970 req/s).
- **PostgreSQL — выбираемая оператором альтернатива SQLite, не второй параллельный код.** `--db-backend=postgres`
  (`StructuredLogDatabase.openPostgres`, `drift_postgres`/`PgDatabase`) переиспользует одну схему `drift` для обоих
  диалектов; отличается только то, что реально не может быть общим: пул соединений — один на чтение и запись
  (`--db-postgres-pool-size`, `--db-read-pool-size` при этом backend'е только предупреждает и ни на что не влияет),
  батч-вставка логов — отдельная Postgres-ветка (`RETURNING *` вместо `last_insert_rowid()` + диапазон id, диапазон
  для Postgres в общем случае небезопасен), фильтр по `context.<key>` — `jsonb`'s `#>>` вместо `json_extract`
  (с задокументированной асимметрией `true`/`false` против `1`/`0`), и плейсхолдеры сырого SQL — `?` под Postgres
  не работает вовсе (`42601: syntax error`), каждый рукописный фрагмент прогоняется через `placeholdersForDialect`
  — и тот **пересчитывает** `?` против числа связанных переменных, на обоих диалектах. Проход нумерует
  каждый `?` подряд, поэтому `?` внутри строкового литерала уехал бы в `$n` и сменил смысл запроса —
  на PostgreSQL, пока SQLite работает и прогон по умолчанию зелен. Несовпадение — `StateError` (не
  `assert`: он выключен ровно в той сборке, где испорченный запрос и выполнится), и оно видно там,
  где тесты реально идут.
  Найдено и исправлено на практике, не юнит-тестом: `PgDatabase.opened(pool)` не закрывает переданный пул при
  `close()` — без фикса процесс не завершался по `SIGTERM` (`StructuredLogDatabase._ownedPool` + переопределённый
  `close()`, мутацией подтверждено). Тесты — тег `postgres` (`dart_test.yaml`), обязательно с `--concurrency=1`:
  файлы делят одну физическую базу без пер-файловой изоляции, в отличие от SQLite'шного `NativeDatabase.memory()`.
  Полная запись решения — [openspec/changes/add-postgres-backend/](openspec/changes/add-postgres-backend/).
- **Типизированный билдер drift тоже расходится по диалектам, и зелёный CI об этом не скажет.** Пункт выше
  перечисляет расхождения там, где SQL написан руками; но их порождает и билдер. `isNotValue` рендерит
  null-safe `IS NOT <value>` — SQLite принимает, PostgreSQL отвергает вовсе (`IS NOT` там берёт только
  NULL/TRUE/FALSE, и запрос умирает как `42601: syntax error at or near "$3"`, не сравнив ничего). Так в #54
  сломалась смена пароля на всяком развёртывании с `--db-backend=postgres`: bootstrap-админ обязан сменить
  временный пароль прежде всего остального, и **свежее развёртывание не работало целиком** (починено в #59
  заменой на `equals(...).not()`). **Правило: запрос, собранный чем-то сложнее `equals`/`isNull`/`isIn`,
  требует кейса под тегом `postgres`** — там диалекты и перестают совпадать. Механика провала важнее самого
  промаха: все тесты сервера по умолчанию идут на `NativeDatabase.memory()`, то есть на SQLite, и **зелёный
  прогон означает лишь «под тегом `postgres` нет теста на этот путь»**, а не «на PostgreSQL работает». Найдено
  не тестом, а поднятием docker-compose против PostgreSQL и входом bootstrap-админом — первым, что делает
  оператор.
- **Правило валидации, выведенное замером одного бэкенда, — это правило про этот бэкенд, а не про эндпоинт.**
  Пункт выше требует кейса под тегом `postgres` для запроса; этого оказалось мало. #61 отклонял пустой сегмент
  в ключе `context.<key>`, и границу «пустого» установил замером: `json_extract` SQLite отвергает `$.` и `$..`,
  а `$.a.` читает как `$.a` — значит висячая точка безобидна и отклонять её не за что. На PostgreSQL строки-пути
  нет вовсе: ключ разбивается в литерал массива (`log_filter.dart`), `a.` даёт `{a,}`, и это
  `22P02: malformed array literal` — `500` с голым `Internal Server Error` вместо конверта, на строке, которую
  пользователь набрал в фильтре (починено в #64 заменой четырёх правил одним: «ни один сегмент не пуст»).
  **Второй промах того же рода после #59, и в этом его главный смысл**: правило выше было уже записано, но
  говорило про запросы, — а сюда `500` приехал через валидацию. Поэтому кейс под тегом `postgres` нужен и тогда,
  когда изменение не трогает ни одного запроса, но опирается на измеренное поведение SQLite. Оба дефекта найдены
  одинаково — поднятием стенда против PostgreSQL и работой в нём как оператор; тесты при этом были зелёными оба
  раза.
- **Живая подписка пишет в сокет раз за ход цикла событий, а не раз на запись, и кодирует запись один раз на всех.**
  `deliverLive` кладёт кадры в исходящую очередь подписки, `Timer.run` сливает её одним `body.add`; кадр записи
  (`_eventBytes`) кодируется один раз на объект `LogEntry` (`Expando`) — подписчики группы получают один и тот же
  объект из `LogBroadcast`. Слив стоит на таймере, а не в микрозадаче: broadcast-контроллер раздаёт пачку по одному
  событию на микрозадачу, и сброс, вставший между ними, писал бы каждую запись отдельно (проверено: тест на «одну
  запись на пачку» краснел). Порядок и байты те же. На 1000 подписчиков: p50 доставки 181 → 9 мс, сервер 1,15 → 0,28
  ядра; при 200 подписчиках чтение рядом (p95) 61 → 6 мс. Системный вызов `write` на сокет был ~60 % главного изолята.
- **Зависимости сервера под `cherrypick_generator`: `sdk ^3.9.0`, `freezed ^3`, `drift`/`drift_dev` 2.31.**
  Генератору нужны `build ^4` и `analyzer ^9`, поэтому `freezed` 2.x (`build ^2`) не подходит, а `freezed` 4.x не
  подходит тоже: ему нужен `analyzer ^13/^14` (для 4.x не хватило бы и Dart 3.11, но упирается он именно в
  `analyzer`). Пока генератор держит `analyzer ^9`, `freezed` остаётся на `^3.0.0`. Поднятие нижней границы `sdk`
  до 3.9 сменило стиль `dart format` для всего пакета (стиль зависит от языковой версии пакета), поэтому
  переформатирование всех файлов пакета — отдельный механический коммит, а не правка логики.
- **Граф объектов сервера объявлен модулями `cherrypick`, а не собран в `buildHandler` (этап 2 перехода на DI).**
  `openServerScope` (`http/server.dart`) открывает **свой** скоуп на каждый вызов (не глобальный корень: тесты строят
  много обработчиков на своих БД) и ставит в него `AppModule` (`http/app_module.dart`, рукописный: несёт настройки
  и `LogBroadcast`, которые ему *дают*) и пять генерируемых модулей рядом с фичами (`rbac_module`, `audit_module`,
  `auth_module`, `storage_module`, `http/routes_module`; `*.module.cherrypick.g.dart` не коммитятся). Значения
  (`TokenSettings`, `HttpSettings`) — объекты, а не строки/числа: контейнер связывает по типу, а именованная строка —
  это имя, которое никто не проверяет. `buildHandler` **сразу разрешает все маршруты**, поэтому нерезолвимый тип падает
  при построении обработчика — в каждом тесте, который его строит, и на старте настоящего сервера, — а не на первом
  запросе. Генератор графа не проверяет: `test/di/server_scope_test.dart` разрешает остальное и закрепляет, что
  конфигурация доходит до маршрутов (мутацией проверено: убрать `IdentityProvider` или не передать лимит тела — тесты
  красные). **Граф разложен на слои по зависимостям, а не по фичам** (`serverScopeName` — сам скоуп — ← `infra` ← `services` ←
  `app` ← `host`): в самом скоупе — то, что серверу *дают* (`AppModule`: настройки, broadcast и, у процесса, логирование);
  в `infra` — БД и воркеры хэширования (`InfraModule`); в `services` — то, что строится из них и не отдаёт маршрутов
  (`Authorizer`, `AuditWriter`, токены, `IdentityProvider`, `LogStore`); в `app` — маршруты; в `host` — то, что есть только
  у процесса: purge и слушающий сервер (`HostModule`, `openServerHost`). Скоуп на фичу, как на клиенте, не подходит:
  маршруты всех фич используют одни сервисы, а скоуп резолвит **вверх**, но не вбок.
  **Жизненный цикл (этап 3): остановка — это один вызов `CherryPick.closeScope`.** Закрытие скоупа сначала закрывает
  вложенные, потом свои `Disposable` (проверено по исходникам и тестом с шпионом на каждый слой: порядок
  `host → app → services → infra → сам скоуп`), так что сервер и purge останавливаются первыми, БД и воркеры — после
  всего, что ими пользуется, а логирование сбрасывается последним. Внутри слоя порядок не гарантирован, поэтому то, что
  должно закрываться друг за другом, разнесено по слоям. **Скоуп закрывает только то, что его биндинги *создали***:
  переданный `toInstance` не закрывается, поэтому то, чем владеет процесс (БД, пул хэширования, логирование), привязано
  провайдером, а созданным оно становится, только когда его *разрешили* — `openServerScope` разрешает их сразу
  (мутацией проверено: без этого пул не закрывается). Владеет ли скоуп ими, решает вызывающий: `ProcessResources`
  (только `bin/server.dart`); тесты строят много обработчиков на своих БД и делят один пул хэширования на изолят, и их
  скоуп ничего вне себя не закрывает. `ServerHost` (`http/server_host.dart`) закрывает broadcast **до** сокета:
  `HttpServer.close` возвращается, не дожидаясь открытых соединений, а подписка сама не заканчивается — без закрытия
  broadcast процесс не мог бы выйти; порядок обратен зависимости, потому и записан в классе, а не оставлен контейнеру.
  `openServerScope` возвращает самый внутренний слой графа, `serverGraphIsBuilt(root)` отвечает, построен ли граф.
  **Настоящий сервер открывает граф через helper**: `bin/server.dart` делает `CherryPick.openScope(scopeName:
  serverScopeName)`, строит обработчик в нём (`buildHandler(scope:, process:)`), открывает слой `host`, стартует
  `PurgeScheduler` и `ServerHost` в нужном порядке и по сигналу закрывает скоуп. Проводка наблюдается на настоящем
  процессе: `server.graph_opened` (с `populated`) и `server.graph_closed` на уровне debug
  (`test/bin/server_integration_test.dart`), purge-тест и SIGTERM при открытой подписке (`packages/e2e`,
  `shutdown_test.dart`). `buildHandler` без `scope` (тесты) по-прежнему берёт свой изолированный `Scope`. Сигнатура
  `buildHandler` не менялась (добавились необязательные `scope` и `process`), поэтому 32 конструктора маршрутов и 9
  вызовов в тестах остались как были.
- **Наблюдатель и детекция циклов контейнера включаются одним вызовом `configureContainer(log)`** (`di/container_setup.dart`;
  `bin/server.dart` зовёт его до `CherryPick.openScope`, потому что скоуп берёт глобальный наблюдатель при создании).
  `StructuredLogCherryPickObserver` пишет в собственный журнал сервера: скоупы, модули и освобождение — на debug, цикл,
  предупреждение и ошибку — выше; **запросы и создание экземпляров не пишутся, экземпляр не печатается никогда** (граф
  держит `TokenSettings` с секретом подписи; процессный тест проверяет, что секрет не попадает в журнал). Это реализация
  интерфейса, а не наследник `SilentCherryPickObserver`: контейнер не зовёт наблюдателя, который им является. Детекция
  циклов (локальная и межскоуповая) остаётся включённой и в проде: цикл — ошибка проводки, а не её отсутствие означало бы
  переполнение стека на старте. Доходит только до скоупов, открытых через helper: изолированные `Scope` тестов — нет,
  намеренно. Два предупреждения про `cherrypick` 4.0.0-dev.5: `onInstanceDisposed` контейнер **никогда не вызывает**
  (закрытие видно только по `di.scope_closed` для `closeSubScope`; закрытие вложенных слоёв событий не даёт — порядок
  проверяется тестом со шпионами, не журналом), а межскоуповый детектор циклов — синглтон, который запоминает
  наблюдателя первого создания, поэтому в тестах в одном изоляте «услышит» не тот наблюдатель. Процессный тест
  (`test/bin/server_integration_test.dart`) наблюдает `di.modules_installed` для каждого модуля и `di.scope_closed`
  (мутацией проверено: убрать `configureContainer` — красный).
- Собственная диагностика сервера идёт только через `structured_log`
  (`lib/src/logging/setup.dart`), `print`/`debugPrint`/`dart:developer`
  запрещены и проверяются стражем `test/logging/no_print_test.dart`. Три
  журнала не смешиваются: `log_entries` — данные тенантов, `audit_log_entries`
  — аудит, собственный лог — диагностика процесса; в лог никогда не попадают
  пароли, токены, секретные ключи и тела запросов (тесты
  `test/logging/diagnostics_isolation_test.dart`).
- HTTP-слой: ограничение частоты (`rate_limit_middleware.dart`) стоит в `Pipeline` **до** аутентификации — отклонённый по адресу запрос не должен стоить серверу даже разбора тела; субъектная половина ограничителя вызывается из хендлера (`request.rateLimitAttempt`), потому что субъект известен только ему. Аутентификация — один резолвящий middleware в общем `Pipeline` (`principal_middleware.dart`), а не обёртка на маршруте; хендлер объявляет требуемого принципала сам (`request.requireUser()`/`requireProject()`), и это обязано быть первой строкой — до парсинга path-параметров и любого обращения к БД, иначе 404 о несуществующей строке утекает неаутентифицированному вызывающему. Маршруты задаются аннотациями `@Route.<verb>` на методах классов `*Routes` и собираются `shelf_router_generator`; `buildHandler` только монтирует сгенерированные роутеры. Новый маршрут обязан появиться в таблице `test/http/route_auth_matrix_test.dart` — иначе тест падает.
- `publish_to: none` — самостоятельный сервис, а не библиотека для `pub.dev`.

Внутри [packages/e2e/](packages/e2e/):

- `structured_log_e2e` (`publish_to: none`) — поднимает `bin/server.dart` **настоящим процессом** и
  гоняет через него всю цепочку: `structured_log` → `HttpLogOutput` → сервер → `ApiClient` и
  репозитории admin-клиента → SSE. Существует потому, что все остальные наборы останавливаются на
  шве: серверные тесты собирают хендлер, клиентские отвечают подставным адаптером, тесты отправщика
  говорят с заглушкой — а оба дефекта 15.09.2026 жили ровно в швах.
- Flutter-пакет (`flutter test`), не Dart: импортирует admin-клиент, а тот — Flutter-пакет.
- `dependency_overrides` с путями прописаны **в самом `pubspec.yaml`**, а не оставлены
  `melos bootstrap`: CI идёт без melos, а hosted-`structured_log` тянул бы опубликованную версию.
- В `melos.yaml` заведён отдельный скрипт `test:e2e` — в общий `test` набор не входит: каждый файл
  платит за `dart run` сервера и требует сгенерированного кода сервера и клиента.
- **Браузерный слой не покрыт** (решение пользователя 15.09.2026). Класс «на web ведёт себя иначе» —
  как неумение dio стримить — этими тестами не ловится.

Внутри [deploy/](deploy/):

- `docker-compose.yml` — три сервиса: `server` (образ из
  [backend/structured_log_server/Dockerfile](backend/structured_log_server/Dockerfile)), `web`
  (образ из [frontend/structured_log_admin_client/Dockerfile](frontend/structured_log_admin_client/Dockerfile) —
  только статика клиента, о `server` не знает вовсе) и `proxy` (готовый `nginx:1.27-alpine`,
  настроенный [deploy/proxy/nginx.conf.template](deploy/proxy/nginx.conf.template) — ставит `web`
  и `server` за один origin: `/v1/` на `server`, остальное на `web`). Разделение на отдельный
  `proxy` вместо проксирования внутри `web`, как было раньше, — решение по итогам инцидента:
  зашитый в nginx-конфиг `web` адрес `server` требовал, чтобы `server` резолвился просто для
  *запуска* контейнера `web`, даже в топологии, где до этого внутреннего proxy трафик вообще не
  доходил (найдено при развёртывании в Kubernetes с раздельными путями Ingress — см.
  `docs/guides/admin-guide.md#ingress-routing`). Порты `server` и `web` наружу **не** публикуются,
  наружу смотрит только `proxy`.
- **Один origin остаётся образцовым способом развёртывания, а не единственно возможным.**
  По умолчанию CORS в сервере нет: браузерный клиент с другого хоста не сможет обратиться к API,
  поэтому клиент отдаётся рядом с API, а его бандл собирается с пустым base URL. С 2026-09
  сервер умеет включать CORS явно — `--cors-allowed-origins` (`add-server-cors`), список origin
  через запятую, пусто по умолчанию — для случаев вроде локальной разработки на хосте без
  этого `docker-compose`. `docker-compose.yml` этой настройкой не пользуется: единый origin
  остаётся тем, что здесь развёртывается.
- `deploy.sh` — собирает web-бандл клиента **на хосте** тем же FVM-SDK, что и весь репозиторий, и
  копирует готовый `build/web` в nginx-образ: официального Docker-образа Flutter не существует, а
  стороннему в цепочке деплоя не место. Он же генерирует `secrets/jwt_secret` при первом
  запуске.
- Секрет подписи — файл (`<VAR>_FILE`), а не переменная окружения: файл не виден ни в
  `docker inspect`, ни в списке процессов. `deploy/.env` и `deploy/secrets/` — в `.gitignore`.
- `TRUSTED_PROXY_HOPS=1` задан в compose осознанно: сервер отсчитывает хопы справа от
  `X-Forwarded-For`, и неверное значение либо позволяет подделать адрес, либо сваливает всех в одну
  корзину лимитера.
- Контекст сборки обоих образов — **корень репозитория**, поэтому `.dockerignore` лежит там же
  (копия рядом с Dockerfile молча игнорируется). Сборочные директории перечислены поимённо, а не
  глобом `**/build/`: `build/web` клиента — это как раз то, что копируется в образ, а исключённую
  глобом директорию обратно не включить.
- **Имя переменной секрета — `STRUCTURED_LOG_JWT_SECRET`**(`_FILE`), как в decision 47 `design.md` и во
  всей `docs/operations/`. Реализация какое-то время звала параметр `jwt-signing-secret`; расхождение
  устранено переименованием кода (задача 35.6), потому что обоснования у длинного имени не нашлось
  ни в одном решении.

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
  --exclude-tags integration --exclude-tags postgres`, затем отдельным шагом
  `dart test --tags integration` (поднимает `bin/server.dart` процессом; тег
  объявлен в `dart_test.yaml`, но не исключён — разделение нужно только чтобы
  в логе было видно, какой из прогонов упал), затем `dart test --tags
  postgres --concurrency=1` против сервис-контейнера `postgres:16-alpine`
  (health check `pg_isready`, раннер сам не пускает шаги до готовности —
  ручного wait-loop, в отличие от `chromedriver` ниже, не нужно; тег
  диалект-чувствителен, `--concurrency=1` обязателен — Postgres-тегированные
  файлы делят одну физическую базу без пер-файловой изоляции и портят друг
  другу фикстуры на дефолтной параллельности, см.
  [openspec/changes/add-postgres-backend/](openspec/changes/add-postgres-backend/)) —
  только
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
- `admin-client-flow` — браузерный прогон пути оператора для
  `frontend/structured_log_admin_client`: `flutter pub get`, `build_runner`,
  поднятие `chromedriver` на 4444 (ждёт, пока тот ответит, иначе следующий шаг
  гонится с ещё не занятым портом), затем `flutter drive` по
  `integration_test/user_flow_test.dart`. Отдельной джобой, а не строкой
  матрицы ниже: это **не** `flutter test` — тот биндинг подменяет ввод и
  отвечает 400 на любой HTTP, и дефект, который эта джоба стережёт (диалог,
  закрывавший себя дважды и уносивший единственный показ секретного ключа),
  под ним не воспроизводится вовсе. `-d web-server`, **не** `-d chrome`: со
  вторым Flutter поднимает браузер сам, драйвер не получает WebDriver-сессию и
  прогон висит, ничего не сообщая. Headless — по умолчанию для этой команды.
- `site` — сборка сайта: `npm ci` + `npm run build` в [site/](site/) на Node 22,
  без Dart/Flutter вовсе (Astro-проект вне Melos-workspace). Проверяется
  именно «производит ли `docs/` сайт, который собирается», а не «актуален ли
  закоммиченный вывод»: вывода в репозитории нет, `src/content/docs/` (кроме
  двух посадочных страниц) генерируется хуком `prebuild` из
  `scripts/migrate_docs.py`. Значит правка в `docs/**` может уронить эту джобу,
  не тронув ни строчки Dart: падает либо сам генератор на том, чего не ожидал,
  либо сборка Astro на том, что он произвёл. **Ссылки при этом не проверяются**
  — валидатора в `astro.config.mjs` нет, так что битая ссылка внутри `docs/`
  проходит и CI, и эту джобу молча.
- `flutter` — для Flutter-пакетов (`structured_log_flutter`, `structured_log_material`
  (+`example/`), `structured_log_fluent` (+`example/`), `structured_log_cupertino`
  (+`example/`), `structured_log_admin_ui` (+`example/`), `structured_log_admin_client`), по одному
  матричному прогону на пакет: `flutter pub get`, `dart format --set-exit-if-changed`,
  `flutter analyze`, `flutter test`. Для `structured_log_admin_client` между `pub get` и
  `format` вставлен условный (`if: matrix.package == ...`) шаг `build_runner` — кодогенерация нужна
  только ему.
  Только `ubuntu-latest` — этим пакетам не нужна ОС-чувствительная проверка ротации файлов.
  Использует `subosito/flutter-action`, канал `stable`.

## Перед завершением изменения

1. `dart analyze` — не должно быть замечаний.
2. `dart test` — все тесты должны проходить. **Для `structured_log_server` нужен кейс под
   тегом `postgres`, если изменение трогает запрос к БД, собранный чем-то сложнее
   `equals`/`isNull`/`isIn`, — или опирается на измеренное поведение SQLite, даже когда
   запроса не трогает вовсе.** Прогон по умолчанию идёт на SQLite (`NativeDatabase.memory()`),
   и зелёный он потому, что PostgreSQL никто не спросил (см. два пункта про диалекты в
   разделе о сервере).
3. `dart format --set-exit-if-changed .` — код должен быть отформатирован.
4. При изменении публичного поведения пакета обновлять его `README.md`/`README.ru.md`
   ([emb/structured_log/](emb/structured_log/README.md), [emb/structured_log_flutter/](emb/structured_log_flutter/README.md),
   [emb/structured_log_material/](emb/structured_log_material/README.md), [emb/structured_log_fluent/](emb/structured_log_fluent/README.md),
   [emb/structured_log_cupertino/](emb/structured_log_cupertino/README.md))
   — но не `CHANGELOG.md` (см. «Коммиты и версионирование»).
5. CI ([.github/workflows/ci.yml](.github/workflows/ci.yml)) должен быть зелёным на всех джобах.
