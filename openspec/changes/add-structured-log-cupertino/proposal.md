## Why

Headless-ядро `structured_log_flutter` и два UI-скина (`structured_log_material`, Material 3; `structured_log_fluent`, Fluent UI/WinUI-style) уже реализованы и рабочие, оба доведены до «можно реально использовать в приложении» состояния и прошли `openspec-verify-change`. `design.md` исходной change (`add-structured-log-flutter`) и `design.md` change `add-structured-log-fluent` оба явно оставили `structured_log_cupertino` как кандидата на отдельный будущий change («макет есть, реализации нет»). iOS/macOS — заметная ниша для Flutter-приложений, и просмотрщик логов, нативно выглядящий на iOS (стандартные Cupertino-паттерны: pushed detail screen, segmented control, pill-style фильтры), расширяет применимость всей экосистемы `structured_log_flutter` без изменений в headless-ядре. Заодно наступил и триггер, который `design.md` change `add-structured-log-fluent` прямо назвал условием для рефакторинга: «третий скин» — момент извлечь canonical-палитру цветов уровня (`logLevelColor`) из дублирующихся копий в `structured_log_material`/`structured_log_fluent` в общее место, `structured_log_flutter`, пока дублирование не стало тройным.

## What Changes

- Добавить `structured_log_cupertino/`: просмотрщик логов на встроенных Cupertino-виджетах Flutter SDK (без сторонней UI-библиотеки, в отличие от `fluent_ui`) поверх `LogViewerController` из `structured_log_flutter` — по фирменным iOS-паттернам вместо Material/Fluent: `CupertinoSearchTextField` для поиска, горизонтальный ряд pill-кнопок (`LogCategoryFilterBar`) для динамического фильтра по категории, `CupertinoSlidingSegmentedControl` для фиксированного набора уровней, и, что самое заметное отличие от обоих других скинов — адаптивный детальный вид: на узких экранах тап по записи **пушит** новый экран через `CupertinoPageRoute` (паттерн Почты/Настроек на iPhone), на широких/iPad-размерах список и панель деталей показываются рядом (master-detail split, как на iPad).
- Как и `structured_log_fluent`/`structured_log_material`, пакет сразу получает встраиваемый виджет (`CupertinoLogViewer`, без собственной хромы) отдельно от полноэкранной обёртки (`CupertinoLogViewerPage`) — то, что для двух предыдущих скинов потребовало отдельного рефакторинга уже после первого релиза, здесь сразу в архитектуре.
- **Рефакторинг `structured_log_flutter`**: извлечь `logLevelColor(LogLevel, Brightness)` из `structured_log_material`/`structured_log_fluent` (где она была осознанно задублирована — см. Decision 3 `design.md` change `add-structured-log-fluent`) в `structured_log_flutter/lib/src/log_level_colors.dart`, единственный источник для всех скинов. `structured_log_material`/`structured_log_fluent` реэкспортируют её из своих barrel-файлов — публичный API (`import 'package:structured_log_material/structured_log_material.dart' show logLevelColor`) не меняется, meняется только откуда она физически берётся. `logLevelAbbreviation()` (специфична для компактного бейджа `structured_log_fluent`) остаётся в `structured_log_fluent` — она не нужна ни `structured_log_material`, ни `structured_log_cupertino`.
- Расширить существующую CI-джобу `flutter` матрицей на новый пакет (и его `example/`).

## Capabilities

### New Capabilities
- `flutter-log-viewer-cupertino`: готовый к использованию просмотрщик логов на встроенных Cupertino-виджетах (iOS-style: pushed detail screen на узких экранах, master-detail split на широких) поверх `flutter-log-viewer-core`, аналог `flutter-log-viewer-material`/`flutter-log-viewer-fluent`, но под iOS-конвенции.

### Modified Capabilities
- `flutter-log-viewer-core`: добавляется `logLevelColor(LogLevel, Brightness)` как публичная утилита — общая canonical-палитра для всех скинов (была реализована по одной копии в каждом из `flutter-log-viewer-material`/`flutter-log-viewer-fluent`).

## Impact

- Новый пакет `structured_log_cupertino/`: `pubspec.yaml` (зависимости — `flutter` sdk, `structured_log` `^0.2.0` hosted, `structured_log_flutter` `^0.1.0-dev.2` hosted, `cupertino_icons` — единственная сторонняя runtime-зависимость, нужна для шрифта иконок `CupertinoIcons`), `lib/`, `test/`, `example/` (по аналогии со `structured_log_fluent/example/`, web-таргет).
- `structured_log_flutter/lib/src/log_level_colors.dart`: новый файл (публичная функция `logLevelColor`), экспортирован из barrel-файла пакета.
- `structured_log_material/lib/src/log_level_colors.dart`: удалён; barrel-файл реэкспортирует `logLevelColor` из `structured_log_flutter`.
- `structured_log_fluent/lib/src/log_level_colors.dart`: сокращён до одной `logLevelAbbreviation()`; barrel-файл реэкспортирует `logLevelColor` из `structured_log_flutter`.
- `melos.yaml`: пакет добавляется в `packages:` и в scope скрипта `test:flutter`.
- CI ([.github/workflows/ci.yml](../../.github/workflows/ci.yml)): матрица джобы `flutter` расширяется на `structured_log_cupertino` и `structured_log_cupertino/example`.
- `structured_log` не затрагивается.
