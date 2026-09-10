## 1. structured_log_fluent (Fluent-скин)

- [x] 1.1 Скаффолдинг пакета: `pubspec.yaml` (зависимости: `flutter` sdk, `structured_log` `^0.2.0` hosted, `structured_log_flutter` через `path:` — не опубликован, `fluent_ui` **зафиксирован точно на `4.15.1`**, не диапазоном — см. `design.md` Open Questions: последняя `4.16.1` не компилируется с используемым Flutter SDK), `lib/`, `test/`; `LICENSE` скопирован
- [x] 1.2 Виджет списка записей (`FluentLogViewerPage`): заголовок сверху, сортировка «новые сверху» (`visibleEntries.reversed`), живое обновление через `AnimatedBuilder` на `LogViewerController`
- [x] 1.3 Строка записи (`LogEntryTile`): индикатор уровня (цветной badge с аббревиатурой), временная метка, `event`, тег `category` (если задан); hover-подсветка и accent-выделение выбранной строки через `HoverButton`
- [x] 1.4 Верхняя панель: заголовок «Logs», `TextBox` поиска (→ `searchQuery`), `ComboBox` фильтра по уровню (→ `levelFilter`), `IconButton`+`Tooltip` паузы/возобновления и очистки — по Fluent-макетам из [Log Viewer UI Concepts](https://claude.ai/code/artifact/400091b3-da51-4f73-a1fb-2ce779515de0). **Отклонение от спеки, сама спека поправлена**: буквальный виджет `CommandBar` не используется — его `primaryItems` рассчитаны на компактные кнопки, а не на широкий `TextBox`/`ComboBox` (при попытке засунуть их внутрь `CommandBar` ломалась его логика переполнения — элементы уезжали за пределы экрана); вместо этого кастомный `Row`
- [x] 1.5 Master-detail split view (`LogEntryDetailPane`): выбор строки показывает полный контекст записи в панели справа (список остаётся виден, не модальное перекрытие) + действие копирования в буфер обмена; по умолчанию выбрана самая новая запись
- [x] 1.6 Empty-state (`LogViewerEmptyState`) с двумя вариантами: «No logs yet» (без действия сброса) и «No results found» (с кнопкой «Clear filters»)
- [x] 1.7 Тема — из `FluentTheme.of(context)`/`theme.resources` (светлая/тёмная); canonical-таблица цветов уровня лога в `log_level_colors.dart` (те же значения, что в `structured_log_material` — см. `design.md` Decision 3: дублируется осознанно, не выносится в `structured_log_flutter`)
- [x] 1.8 Виджет-тесты на каждый сценарий из `specs/flutter-log-viewer-fluent/spec.md` — 16 тестов (`flutter test`), все проходят. При написании тестов вскрылись две проблемы окружения/дизайна, обе исправлены: (а) дефолтный тестовый вьюпорт 800×600 слишком узкий для шапки — расширен до 1200×800 в тестах; (б) в master-detail список и панель видны одновременно, поэтому `find.text(event)` может найти два совпадения — введены скоуп-хелперы `_inList`/`_inDetailPane`
- [x] 1.9 `example/`: `flutter create --platforms=web`, демо-приложение (`ExampleApp`/`DemoHome`, зарегистрировано в `melos.yaml` как `structured_log_fluent_example`), подключающее `LogBuffer` к `LogSink` и встраивающее `FluentLogViewerPage`; `flutter test` (2 теста) и `flutter build web` проходят

## 2. CI

- [ ] 2.1 Расширить матрицу существующей джобы `flutter` в [.github/workflows/ci.yml](../../.github/workflows/ci.yml) пакетами `structured_log_fluent` и `structured_log_fluent/example`
- [ ] 2.2 Убедиться, что CI зелёный на всех джобах (старых и новых)

## 3. Документация и финализация

- [ ] 3.1 `README.md`/`README.ru.md` для `structured_log_fluent` (установка, быстрый старт, справочник API, ссылка на `structured_log_material` и `structured_log_flutter`); добавить пакет в корневой [README.md](../../README.md)/[README.ru.md](../../README.ru.md) и в [AGENTS.md](../../AGENTS.md)
- [ ] 3.2 Прогнать `openspec-verify-change` перед архивацией этого change
