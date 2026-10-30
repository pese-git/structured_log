# emb/structured_log_material — заметки для агентов

Дополняет корневой [AGENTS.md](../../AGENTS.md) (проект, команды, соглашения, версионирование, CI). Подгружается, когда работа идёт в этом каталоге; `CLAUDE.md` рядом — симлинк на этот файл.
- [lib/structured_log_material.dart](lib/structured_log_material.dart) — barrel-файл экспорта; реэкспортирует `logLevelColor()` из `structured_log_flutter` (собственной копии палитры у пакета больше нет).
- [lib/src/material_log_viewer.dart](lib/src/material_log_viewer.dart) — `MaterialLogViewer`: встраиваемый виджет без своей хромы (тулбар поиска/паузы/очистки, чипы категории и уровня, список); ниже брейкпоинта master-detail — список + модальный `LogEntryDetailSheet` по тапу, на и выше него — список и немодальная `LogEntryDetailPanel` рядом.
- [lib/src/material_log_viewer_page.dart](lib/src/material_log_viewer_page.dart) — `MaterialLogViewerPage`: тонкая обёртка `Scaffold`/`AppBar` (заголовок «Logs») вокруг `MaterialLogViewer` для полноэкранного сценария.
- [lib/src/log_category_chips.dart](lib/src/log_category_chips.dart) — `LogCategoryChips`: ряд `ChoiceChip` фильтра по `category`, скрывается при <2 категориях.
- [lib/src/log_entry_tile.dart](lib/src/log_entry_tile.dart) — `LogEntryTile`: строка списка (уровень/время/event/category); `selected` подсвечивает запись, показанную в `LogEntryDetailPanel`.
- [lib/src/log_entry_detail_sheet.dart](lib/src/log_entry_detail_sheet.dart) — `LogEntryDetailSheet`: модальный bottom sheet с полным контекстом записи и копированием (узкие экраны).
- [lib/src/log_entry_detail_panel.dart](lib/src/log_entry_detail_panel.dart) — `LogEntryDetailPanel`: тот же контент, что в `LogEntryDetailSheet`, но немодальной панелью для master-detail split (широкие экраны).
- [lib/src/log_viewer_empty_state.dart](lib/src/log_viewer_empty_state.dart) — `LogViewerEmptyState`: «логов ещё нет» / «нет по фильтру».
- [test/](test/) — виджет-тесты (`flutter test`).
- [example/](example/) — полноценное Flutter-приложение (`structured_log_material_example` в `melos.yaml`), запускается через `fvm flutter run -d chrome` (или `-d web-server`) из этой директории; поддерживает web; демонстрирует и `MaterialLogViewerPage`, и встроенный `MaterialLogViewer` в боковой панели.

Общее для трёх скинов (подписи, копирование, русская раскладка) — в [emb/structured_log_flutter/AGENTS.md](../structured_log_flutter/AGENTS.md#общее-для-трёх-скинов).
