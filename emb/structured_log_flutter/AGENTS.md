# emb/structured_log_flutter — заметки для агентов

Дополняет корневой [AGENTS.md](../../AGENTS.md) (проект, команды, соглашения, версионирование, CI). Подгружается, когда работа идёт в этом каталоге; `CLAUDE.md` рядом — симлинк на этот файл.
- [lib/structured_log_flutter.dart](lib/structured_log_flutter.dart) — barrel-файл экспорта.
- [lib/src/log_buffer.dart](lib/src/log_buffer.dart) — `LogBuffer`: кольцевой буфер (`ListQueue`),
  `capture()` подключается как `OutputFunction`/`LogSink.output`, отдаёт записи как
  `ValueListenable`. **Уведомление — одно на пачку, а значение всегда актуально** (decision 14
  `harden-structured-log-core`): `capture` сбрасывает снимок, `entries.value` собирает
  `List.unmodifiable` при первом чтении после изменения (повторное чтение — тот же список), а
  слушателей зовёт одна `scheduleMicrotask` на пачку. Откладывать само значение пробовали и
  отказались: отстающее от `capture` значение ломало бы синхронное чтение —
  `LogViewerController.paused` замораживает именно `entries.value`. Микрозадача, а не кадр
  `SchedulerBinding`: пакет работает и тестируется без живого `WidgetsBinding`. `clear()` уведомляет
  сразу и гасит ожидающее уведомление — это действие пользователя.
- [lib/src/debug_print_output.dart](lib/src/debug_print_output.dart) — `debugPrintOutput`: одна
  строка через `debugPrint`, без ANSI — `HH:mm:ss.SSS LEVEL event key=value…` (местное время из
  `timestamp`), значения экранирует `formatLogfmt` ядра. `debugPrint` выбран ради троттлинга
  (Android не теряет строки при всплеске); длинную строку он не переносит, а logcat режет её после
  ~4 КБ. Выход по умолчанию ядра не меняется — ядро не знает про Flutter.
- [lib/src/log_viewer_controller.dart](lib/src/log_viewer_controller.dart) — `LogViewerController` (`ChangeNotifier`): фильтры по уровню/категории/поиску, пауза, `clear()`; плюс публичная `logLevelOf()`.
- [lib/src/log_level_colors.dart](lib/src/log_level_colors.dart) — `logLevelColor()`: единственный
  источник цветов `LogLevel`, общий для всех скинов (Material/Fluent/Cupertino); живёт здесь, а не в
  конкретном скине, т.к. `Color`/`Brightness` не привязаны ни к одной дизайн-системе — извлечено из
  `structured_log_material`, когда появился третий скин (`structured_log_cupertino`), см.
  `design.md` соответствующей change.
- [lib/src/log_viewer_labels.dart](lib/src/log_viewer_labels.dart) — `LogViewerLabels`: все подписи
  трёх скинов одним объектом (заявка `add-log-viewer-labels`, по Electro #188). **Все поля nullable,
  `null` — умолчание скина**, и умолчания у скинов намеренно разные (`Debug+` у Material/Cupertino,
  `Debug and above` у Fluent): общий английский поменял бы видимые тексты двух скинов. Новая подпись
  в скине = новое поле здесь; тест «все поля маркерами — ни одного английского умолчания» в каждом
  скине краснеет, если забыть.
- [lib/src/log_viewer_localizations.dart](lib/src/log_viewer_localizations.dart) —
  `LogViewerLocalizations`: необязательный делегат с en (пустой набор — умолчания скинов) и ru
  (полный набор, одна формулировка на все скины). **Рукописный, без
  `flutter_localizations`/`intl`/`gen-l10n`** — `LocalizationsDelegate` есть в `flutter/widgets`, а
  `intl` в опубликованной библиотеке ссорил бы версии у потребителей. `resolve(context, labels)` —
  поле за полем: явный `labels` → делегат → умолчание скина; его зовёт **каждый** публичный виджет
  скина, рисующий подписи (одна пропущенная точка — и делегат туда не доходит: так было с `_content`
  пустого состояния Fluent). `Localizations` стоит над `Navigator`, поэтому шторка Material и
  пушнутый экран Cupertino его видят. `flutter_localizations` у скинов — только dev-зависимость
  тестов.
- [test/](test/) — тесты (`flutter test`) на `LogBuffer`, `LogViewerController`, `logLevelColor()`, `LogViewerLabels` и `LogViewerLocalizations`.

## Общее для трёх скинов

Заявка: [../../openspec/changes/archive/2026-10-19-add-log-viewer-labels/](../../openspec/changes/archive/2026-10-19-add-log-viewer-labels/).

- **`labels` и `onContextCopied`** принимают `*LogViewer`, `*LogViewerPage` и публичные составные виджеты; баррели скинов
  реэкспортируют `LogViewerLabels`/`LogViewerLocalizations`. Явный `allLabel` фильтра категорий важнее `labels.allCategories`.
- **Копирование — `lib/src/copy_entry_context.dart`, по копии в каждом скине**: `onContextCopied` зовётся только после
  успешного `Clipboard.setData` и только пока виджет смонтирован; ошибка — в `FlutterError.reportError`, а не
  необработанным `Future`. Своего подтверждения скины не показывают — решение пользователя (шторка Material модальная,
  снэкбар корневого `Scaffold` лёг бы под затемнение).
- **Русские подписи длиннее, и раскладка это уже раз не выдержала**: шапка детального вида всех трёх скинов и строка
  кнопок шторки Material переполнялись на 360/700. Теперь строка «уровень + время» — `Wrap`, кнопка копирования —
  `Flexible` с многоточием, кнопки шторки — `Wrap`. Тесты на русской локали на узкой ширине это стерегут; новая строка
  с подписью рядом с фиксированным элементом требует такого же теста.
- Имена уровней (`INFO`, `INF`, `Debug+`) — идентификаторы `LogLevel`, не подписи; русский набор делегата их не переводит
  (кроме «Все»).
