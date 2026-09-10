## Context

`structured_log_flutter` (headless-ядро: `LogBuffer`, `LogViewerController`) и `structured_log_material` (первый UI-скин, Material 3) уже реализованы, протестированы и прошли `openspec-verify-change` в change `add-structured-log-flutter`. Fluent-макет уже спроектирован в том же canvas — [Log Viewer UI Concepts](https://claude.ai/code/artifact/400091b3-da51-4f73-a1fb-2ce779515de0): command bar вместо app bar, выпадающий список вместо чипов для фильтра по уровню, master-detail split view (список слева, панель деталей справа) вместо bottom sheet, десктопные размеры фреймов (960×640) вместо телефонных.

## Goals / Non-Goals

**Goals:**
- Второй UI-скин поверх уже существующего `LogViewerController`, идиоматичный для Windows/WinUI, по уже готовым макетам.
- Не менять публичное поведение `structured_log`, `structured_log_flutter`, `structured_log_material`.
- Довести до состояния «можно реально использовать в приложении», как и `structured_log_material`.

**Non-Goals:**
- `structured_log_cupertino` — макет есть, реализация — отдельный будущий change.
- Реальная сборка под Windows-desktop в CI (нет Windows-раннера в текущей матрице) — см. Decision 4.
- Адаптивность master-detail под мобильные/узкие экраны.

## Decisions

1. **UI-кит: [`fluent_ui`](https://pub.dev/packages/fluent_ui)**, а не ручная реализация Fluent-виджетов на голом Flutter.
   Альтернатива — собрать `CommandBar`/`ComboBox`/панели самостоятельно, как Material/Cupertino-скины используют только встроенные в Flutter SDK виджеты (без сторонних зависимостей). Отклонено: точное поведение WinUI-контролов (`CommandBar`, `ComboBox`, состояния выбора) — существенный объём работы, а `fluent_ui` активно поддерживается и специально для этого существует; переизобретать его — хуже по результату (менее точно повторяет реальный WinUI) и по затратам.

2. **Master-detail split view вместо bottom sheet** для детального вида записи (список слева, панель контекста справа в том же экране), по готовому Fluent-макету.
   Альтернатива — переиспользовать Material-паттерн (bottom sheet) для консистентности между скинами. Отклонено: весь смысл платформенного скина — соответствовать реальным конвенциям платформы; WinUI-приложения (Почта, Параметры) обычно используют master-detail/split view, а не модальные bottom sheet — это мобильный жестовый паттерн, chужой для десктопного mouse+keyboard интерфейса.

3. **Canonical-палитра цветов уровня дублируется** в `structured_log_fluent/lib/src/log_level_colors.dart` (те же hex-значения, что в `structured_log_material`, ради единого «визуального языка» данных из design-canvas), а не выносится в `structured_log_flutter`.
   Альтернатива — вынести в `structured_log_flutter` как design-system-нейтральную утилиту (`dart:ui`/`package:flutter/painting.dart`'s `Color`/`Brightness` не привязаны ни к одной дизайн-системе — этим слоем пользуются и Material, и Cupertino, и `fluent_ui`). Это ровно тот риск, который `design.md` исходной change прямо пометил «пересмотреть, если появится второй потребитель» — теперь он появился. Осознанно отложено: извлечение задело бы уже реализованный и провалидированный `structured_log_material` (удаление его локального `logLevelColor`, смена публичного API, правки спеки/README) ради узкого изменения, а сама таблица маленькая (~15 строк) и стабильная. Стоит извлечь, когда появится третий скин (`structured_log_cupertino`) — тогда дублирование станет тройным и риск разъезда вырастет.

4. **Пример-приложение таргетится на web** (`flutter create --platforms=web`), как и `structured_log_material/example`, а не на реальный Windows-десктоп.
   Альтернатива — `--platforms=windows` для «настоящей» нативной Fluent-сборки. Отклонено для CI: существующая матрица гоняется на `ubuntu-latest`, Windows-раннера нет; web-рендерер Flutter отрисовывает виджеты `fluent_ui` идентично независимо от хост-ОС, так что CI-проверка остаётся содержательной. Контрибьютор на Windows может локально добавить платформу `windows` и запустить `flutter run -d windows` — это не заблокировано, просто не входит в CI-проверяемый путь.

5. **Именование: `structured_log_fluent`**, без промежуточного `_flutter` — по решению 6 из `design.md` исходной change (`structured_log_material`/`structured_log_cupertino`/`structured_log_fluent`, material/cupertino/fluent однозначно про Flutter и без уточняющего сегмента).

6. **CI: расширить существующую матрицу джобы `flutter`** в [.github/workflows/ci.yml](../../.github/workflows/ci.yml) новым пакетом, а не заводить отдельную джобу/workflow — тот же принцип, что и при добавлении `structured_log_material` в эту матрицу.

## Risks / Trade-offs

- [Риск] `fluent_ui` — первая настоящая сторонняя (вне Flutter SDK) UI-зависимость среди скинов → [Митигейшн] это ожидаемо и заранее обсуждалось (Cupertino/Material идут бесплатно с Flutter SDK, Fluent — нет); версия пиннится диапазоном (`^`), headless-ядро `structured_log_flutter` по-прежнему без зависимости от какой-либо дизайн-системы.
- [Риск] Дублирование canonical-палитры цветов уровня становится двойным (Material + Fluent) вместо единичного → [Митигейшн] осознанно принято сейчас ради узкого diff (см. Decision 3); извлечь в `structured_log_flutter`, когда появится третий скин.
- [Риск] Master-detail плохо смотрится на узких/мобильных экранах → [Митигейшн] Fluent-скин ориентирован на desktop в первую очередь (как и макет); адаптивность под мобильные экраны — вне рамок.
- [Риск] CI не проверяет реальную Windows-сборку → [Митигейшн] см. Decision 4 — web-таргет для example достаточен для содержательной CI-проверки; реальная Windows-сборка — ответственность контрибьютора локально, если понадобится.

## Migration Plan

1. Скаффолдинг `structured_log_fluent/`: `pubspec.yaml` (`flutter` sdk, `structured_log` `^0.2.0` hosted, `structured_log_flutter` через `path:` — не опубликован, `fluent_ui` с pub.dev), `lib/`, `test/`.
2. Реализация виджетов: `FluentLogViewerPage` (command bar + список), строка списка, панель детального вида (master-detail split), empty-state с двумя вариантами, `logLevelColor`.
3. Виджет-тесты на каждый сценарий из `specs/flutter-log-viewer-fluent/spec.md`.
4. `example/`: `flutter create --platforms=web`, демо-приложение (аналогично `structured_log_material/example`).
5. Регистрация в `melos.yaml` (`packages:` + `test:flutter` scope).
6. Расширение CI-джобы `flutter` матрицей на `structured_log_fluent` (+ `example/`).
7. `README.md`/`README.ru.md`.
8. `openspec-verify-change` перед архивацией.
9. Откат: пакет не опубликован — откат через `git revert`; `structured_log`/`structured_log_flutter`/`structured_log_material` не затрагиваются.

## Open Questions

- Точная версия `fluent_ui` для пиннинга — зафиксировать последнюю стабильную на pub.dev на момент реализации.
- Нужна ли реальная платформа `windows` в `example/` (не только `web`) — пока решено ограничиться `web` (Decision 4), можно пересмотреть по запросу.
