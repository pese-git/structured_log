## Why

Headless-ядро `structured_log_flutter` и первый UI-скин (`structured_log_material`, Material 3) уже реализованы и рабочие. `design.md` исходной change явно оставил Cupertino/Fluent-скины как «кандидатов на последующие отдельные change после проверки headless-ядра и первого скина» — эта проверка пройдена (`openspec-verify-change` дал чистый результат). Fluent-макет уже спроектирован (раздел Fluent в canvas [Log Viewer UI Concepts](https://claude.ai/code/artifact/400091b3-da51-4f73-a1fb-2ce779515de0): command bar, выпадающий список для фильтра по уровню, master-detail split view вместо bottom sheet, десктопные размеры фреймов) — реализация не требует нового дизайн-раунда. Windows-desktop — растущая ниша для Flutter, и просмотрщик логов, нативно выглядящий на Windows (`fluent_ui`, WinUI-совместимый стиль), расширяет применимость всей экосистемы `structured_log_flutter` без изменений в headless-ядре.

## What Changes

- Добавить `structured_log_fluent/`: просмотрщик логов на [`fluent_ui`](https://pub.dev/packages/fluent_ui) поверх `LogViewerController` из `structured_log_flutter` — по фирменным Fluent/WinUI-паттернам вместо Material: `CommandBar` вместо app bar с полем поиска, выпадающий список (`ComboBox`) вместо чипов для фильтра по уровню, master-detail split view (список слева, панель деталей справа) вместо modal bottom sheet — по уже готовым Fluent-макетам из [Log Viewer UI Concepts](https://claude.ai/code/artifact/400091b3-da51-4f73-a1fb-2ce779515de0).
- Явно вне рамок этого change: `structured_log_cupertino` (макет есть, реализации нет — кандидат на отдельный будущий change).
- Расширить существующую CI-джобу `flutter` (добавленную в `add-structured-log-flutter`) матрицей на новый пакет.

## Capabilities

### New Capabilities
- `flutter-log-viewer-fluent`: готовый к использованию просмотрщик логов на `fluent_ui` (WinUI-style: command bar, master-detail split view) поверх `flutter-log-viewer-core`, аналог `flutter-log-viewer-material`, но под Windows-desktop конвенции.

### Modified Capabilities
(нет — `flutter-log-viewer-core` и `flutter-log-viewer-material` этим change не затрагиваются)

## Impact

- Новый пакет `structured_log_fluent/`: `pubspec.yaml` (зависимости — `flutter` sdk, `structured_log` `^0.2.0` hosted, `structured_log_flutter` через `path:` — не опубликован, `fluent_ui` с pub.dev), `lib/`, `test/`, `example/` (по аналогии со `structured_log_material/example/`, включая web/desktop-платформу для демонстрации).
- `melos.yaml`: пакет добавляется в `packages:` и в scope скрипта `test:flutter`.
- CI ([.github/workflows/ci.yml](../../.github/workflows/ci.yml)): матрица джобы `flutter` расширяется на `structured_log_fluent` (и его `example/`, если будет создан).
- `structured_log`, `structured_log_flutter`, `structured_log_material` не затрагиваются.
