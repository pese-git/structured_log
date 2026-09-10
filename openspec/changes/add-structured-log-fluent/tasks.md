## 1. structured_log_fluent (Fluent-скин)

- [ ] 1.1 Скаффолдинг пакета: `pubspec.yaml` (зависимости: `flutter` sdk, `structured_log` `^0.2.0` hosted, `structured_log_flutter` через `path:` — не опубликован, `fluent_ui` с pub.dev — зафиксировать последнюю стабильную версию), `lib/`, `test/`; `LICENSE` скопирован
- [ ] 1.2 Виджет списка записей (`FluentLogViewerPage`): `CommandBar` сверху, сортировка «новые сверху», живое обновление от `LogViewerController`
- [ ] 1.3 Строка записи: индикатор уровня (badge/цветовой маркер), временная метка, `event`, тег `category` (если задан)
- [ ] 1.4 Командная панель: заголовок «Logs», поле поиска (→ `searchQuery`), `ComboBox` фильтра по уровню (→ `levelFilter`), переключатель паузы/возобновления, действие очистки — по Fluent-макетам из [Log Viewer UI Concepts](https://claude.ai/code/artifact/400091b3-da51-4f73-a1fb-2ce779515de0)
- [ ] 1.5 Master-detail split view: выбор строки показывает полный контекст записи в панели справа (не модальное перекрытие) + действие копирования в буфер обмена
- [ ] 1.6 Empty-state с двумя вариантами: «логов ещё нет» (без действия сброса) и «нет записей по текущему фильтру» (с действием сброса)
- [ ] 1.7 Тема — из `FluentTheme.of(context)` (светлая/тёмная); canonical-таблица цветов уровня лога в `log_level_colors.dart` (те же значения, что в `structured_log_material` — см. `design.md` Decision 3: дублируется осознанно, не выносится в `structured_log_flutter`)
- [ ] 1.8 Виджет-тесты на каждый сценарий из `specs/flutter-log-viewer-fluent/spec.md`
- [ ] 1.9 `example/`: `flutter create --platforms=web`, демо-приложение (аналогично `structured_log_material/example`), подключающее `LogBuffer` к `LogSink` и встраивающее `FluentLogViewerPage`

## 2. CI

- [ ] 2.1 Расширить матрицу существующей джобы `flutter` в [.github/workflows/ci.yml](../../.github/workflows/ci.yml) пакетами `structured_log_fluent` и `structured_log_fluent/example`
- [ ] 2.2 Убедиться, что CI зелёный на всех джобах (старых и новых)

## 3. Документация и финализация

- [ ] 3.1 `README.md`/`README.ru.md` для `structured_log_fluent` (установка, быстрый старт, справочник API, ссылка на `structured_log_material` и `structured_log_flutter`); добавить пакет в корневой [README.md](../../README.md)/[README.ru.md](../../README.ru.md) и в [AGENTS.md](../../AGENTS.md)
- [ ] 3.2 Прогнать `openspec-verify-change` перед архивацией этого change
