## 1. Ядро: `LogViewerLabels` в `structured_log_flutter`

- [x] 1.1 Добавить `lib/src/log_viewer_labels.dart`: `@immutable` класс с `const`-конструктором, все поля из design (decision 3) nullable, `levelFilterLabel` — `String Function(LogLevel? minLevel)?` (включая `contextHeading`, добавленный при реализации: заголовок `CONTEXT` деталей есть во всех трёх скинах); dartdoc каждого поля называет дефолт каждого скина
- [x] 1.2 Реализовать `copyWith` (без `==`/`hashCode` — поле-функция их не даёт честно сравнить)
- [x] 1.3 Экспортировать из `lib/structured_log_flutter.dart`; проверить, что файл не импортирует ни `material`, ни `cupertino`, ни `fluent_ui`
- [x] 1.4 Тесты `test/log_viewer_labels_test.dart`: пустой набор — все поля `null`; `copyWith` меняет одно поле и не трогает исходный; тип доступен из барреля

- [x] 1.5 Добавить `lib/src/log_viewer_localizations.dart`: `LogViewerLocalizations` (`labels`, `of`, `resolve`), рукописный `LocalizationsDelegate` с `SynchronousFuture`, `isSupported` по `en`/`ru`; английский — `const LogViewerLabels()`, русский — полный набор (формулировки из #188); экспорт из барреля; без новых зависимостей в `pubspec.yaml`
- [x] 1.6 Тесты: русский набор полный и `levelFilterLabel(null) == 'Все'`; английский пуст; `de` не поддерживается; `resolve` — явное поле важнее делегата, без делегата возвращает переданный набор (виджет-тест с `Localizations`)

## 2. Material: `structured_log_material`

- [x] 2.1 `MaterialLogViewer`/`MaterialLogViewerPage` принимают `labels` (по умолчанию `const LogViewerLabels()`) и `onContextCopied`; страница прокидывает оба во вьювер
- [x] 2.2 Заменить литералы тулбара (подсказка поиска, тултипы паузы/продолжения/очистки), подписи фильтра уровня (`levelFilterLabel`) и заголовок страницы на `labels.<поле> ?? '<прежний текст>'`; заголовок `CONTEXT` в шторке и панели — из `labels.contextHeading`
- [x] 2.3 `LogViewerEmptyState`, `LogEntryDetailSheet`, `LogEntryDetailPanel`, `LogCategoryChips` принимают `labels`; `allLabel` у чипов становится `String?` с порядком `allLabel` → `labels.allCategories` → `'All'`
- [x] 2.4 Копирование в шторке и панели: `await Clipboard.setData`, при успехе и `mounted` — `onContextCopied(entry)`, при ошибке — `FlutterError.reportError`, колбэк не зовётся; шторка получает `labels`/`onContextCopied` через `showModalBottomSheet`-билдер
- [x] 2.5 Тесты: без `labels` — прежние тексты; все поля маркерами — на экране (тулбар, чипы, пустые состояния, шторка на узкой ширине, панель на широкой) нет ни одного прежнего английского текста; `allLabel` важнее `labels`; `onContextCopied` вызван один раз с записью (подменённый канал `SystemChannels.platform`); ошибка канала — колбэк не вызван, ошибка в `FlutterError.onError`; без колбэка подтверждения нет
- [x] 2.6 Каждый публичный виджет скина, рисующий подписи, разрешает их через `LogViewerLocalizations.resolve`; тесты: делегат `ru` без `labels` — русские подписи (включая шторка и панель), явный `searchHint` перекрывает делегат

## 3. Fluent: `structured_log_fluent`

- [x] 3.1 `FluentLogViewer`/`FluentLogViewerPage` принимают `labels` и `onContextCopied`; страница прокидывает оба
- [x] 3.2 Заменить литералы командной панели (`Search`, `All levels`, подписи уровней «… and above», тултипы паузы/очистки, `Back to list`), заголовок `CONTEXT` панели деталей и заголовок страницы
- [x] 3.3 `LogViewerEmptyState`, `LogEntryDetailPane`, `LogCategoryComboBox` принимают `labels`; `allLabel` комбобокса — `String?`, дефолт `'All types'`
- [x] 3.4 Копирование в `LogEntryDetailPane` — по той же схеме, что 2.4
- [x] 3.5 Тесты — те же случаи, что 2.5, на широкой (master-detail) и узкой (список → детали → назад) ширине
- [x] 3.6 Каждый публичный виджет скина, рисующий подписи, разрешает их через `LogViewerLocalizations.resolve`; тесты: делегат `ru` без `labels` — русские подписи (включая панель деталей), явный `searchHint` перекрывает делегат

## 4. Cupertino: `structured_log_cupertino`

- [x] 4.1 `CupertinoLogViewer`/`CupertinoLogViewerPage` принимают `labels` и `onContextCopied`; страница прокидывает оба
- [x] 4.2 Заменить подсказку поиска, подписи сегментов уровня, заголовок `CONTEXT` деталей и заголовок страницы; кнопкам паузы и очистки дать `Semantics`-подписи из `labels.pause`/`resume`/`clear` (дефолт `Pause`/`Resume`/`Clear all`)
- [x] 4.3 `LogViewerEmptyState`, `LogEntryDetailPanel`, `LogCategoryFilterBar` принимают `labels`; `allLabel` фильтра — `String?`, дефолт `'All'`; пушнутый `CupertinoPageRoute` деталей получает `labels`/`onContextCopied`
- [x] 4.4 Копирование в `LogEntryDetailPanel` — по той же схеме, что 2.4
- [x] 4.5 Тесты — те же случаи, что 2.5, плюс семантические подписи иконочных кнопок и подписи на пушнутом экране деталей
- [x] 4.6 Каждый публичный виджет скина, рисующий подписи, разрешает их через `LogViewerLocalizations.resolve`; тесты: делегат `ru` без `labels` — русские подписи (включая пушнутый экран деталей), явный `searchHint` перекрывает делегат
- [x] 4.7 Тест на узкой ширине (360) с длинными русскими подписями уровней: сегментированный контрол не переполняется (он в горизонтальном скролле — подтвердить, а не предположить); при переполнении — поправить раскладку

## 5. Документация и проверка

- [x] 5.1 `README.md`/`README.ru.md` четырёх пакетов: раздел о `LogViewerLabels` (пример с русскими подписями) и `onContextCopied` (пример со снэкбаром для Material); в README ядра — что дефолты у каждого скина свои
- [x] 5.2 `docs/guides/embedding-guide.md`/`.ru.md`: короткий абзац «локализация просмотрщика» со ссылкой на README; перегенерировать сайт не нужно (генерируется в CI), но `python3 site/scripts/migrate_docs.py` прогнать локально, чтобы убедиться, что генератор не падает
- [x] 5.3 `AGENTS.md`: упомянуть `LogViewerLabels` в описании `structured_log_flutter` и `onContextCopied`/`labels` у скинов
- [x] 5.4 В каждом из четырёх пакетов: `fvm flutter analyze`, `fvm flutter test --coverage` (покрытие не ниже порогов `tool/coverage_floors.json`), `fvm dart format --set-exit-if-changed .`; примеры (`example/`) анализируются без замечаний
- [x] 5.5 CI зелёный на PR (джоба `flutter`, строки четырёх пакетов и их примеров)
