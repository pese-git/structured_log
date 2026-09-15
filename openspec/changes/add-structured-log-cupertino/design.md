## Context

`structured_log_flutter` (headless-ядро) и два UI-скина — `structured_log_material` (Material 3) и `structured_log_fluent` (Fluent UI/WinUI-style) — уже реализованы, протестированы и прошли `openspec-verify-change` в своих change. Оба последних скина также получили встраиваемый виджет (`MaterialLogViewer`/`FluentLogViewer`, без собственной хромы страницы) и адаптивную вёрстку (реагирующую на собственную ширину виджета, а не окна) — сначала как отдельный follow-up рефакторинг уже после первого релиза каждого скина. `structured_log_cupertino` строится сразу с обоими этими паттернами в архитектуре, без промежуточного шага.

## Goals / Non-Goals

**Goals:**
- Третий UI-скин поверх уже существующего `LogViewerController`, идиоматичный для iOS/iPadOS, по фирменным Cupertino-паттернам, а не переносящий паттерны Material/Fluent один в один.
- Встраиваемый виджет (`CupertinoLogViewer`) и полноэкранная обёртка (`CupertinoLogViewerPage`) с самого начала — паритет с текущим состоянием `structured_log_material`/`structured_log_fluent`.
- Адаптивность под собственную ширину: узкий встраиваемый виджет ведёт себя как экран iPhone (push-навигация в детали), широкий — как iPad (master-detail split), без явного API для переключения режима.
- Извлечь `logLevelColor` в `structured_log_flutter` (было осознанно отложено design.md `add-structured-log-fluent` до появления третьего скина — см. Decision 3 там же).
- Не менять публичное поведение `structured_log`, `structured_log_material`, `structured_log_fluent` (кроме безопасного технического рефакторинга — источник `logLevelColor`, публичный путь импорта не меняется).

**Non-Goals:**
- Публикация `structured_log_cupertino` на pub.dev в этой change — `publish_to: none`, пакет новый, тот же путь, что `structured_log_material`/`structured_log_fluent` уже прошли отдельными более поздними коммитами.
- Реальная сборка под iOS Simulator/устройство в CI (нет macOS/iOS-раннера, используемого для этой цели, в текущей матрице) — см. Decision 5.
- Сторонняя UI-библиотека вроде `fluent_ui` — см. Decision 1.

## Decisions

1. **UI-кит: только встроенные Cupertino-виджеты Flutter SDK** (`package:flutter/cupertino.dart`), без сторонней UI-библиотеки — в отличие от `structured_log_fluent`, которому потребовался `fluent_ui`.
   Альтернатива — сторонний Cupertino-пакет для более полного покрытия iOS-паттернов. Отклонено: Flutter SDK уже поставляет полный набор нужных виджетов (`CupertinoPageScaffold`, `CupertinoNavigationBar`, `CupertinoSearchTextField`, `CupertinoSlidingSegmentedControl`, `CupertinoButton`, `CupertinoPageRoute`) — как и `structured_log_material`, третья сторонняя UI-зависимость не нужна; `fluent_ui` понадобился именно потому, что у Flutter SDK нет `CommandBar`/`ComboBox`-эквивалентов с WinUI-точностью, а для Cupertino такого разрыва нет.

2. **Адаптивный детальный вид: pushed-экран на узких, master-detail split на широких — а не bottom sheet (Material) и не всегда-split (Fluent).**
   Альтернатива А — bottom sheet, как `structured_log_material`, ради визуальной консистентности между скинами. Отклонено: весь смысл платформенного скина — соответствовать реальным конвенциям платформы; iOS HIG резервирует bottom sheet/action sheet под действия и меню, а не под навигацию в детальный вид — таким паттерном в iOS-приложениях (Почта, Настройки, Заметки) служит **push** через `Navigator`, со стандартной анимацией слайда и жестом «смахнуть назад».
   Альтернатива Б — всегда master-detail split, как `structured_log_fluent`, независимо от ширины. Отклонено: Fluent-скин ориентирован на desktop в первую очередь (mouse+keyboard), где split view почти всегда уместен; iOS-приложения explicitly различают iPhone (single-pane, push) и iPad (`UISplitViewController`-подобный split) по ширине экрана — этот скин явно нацелен и на iPhone-размеры тоже, так что воспроизводит именно это адаптивное поведение, а не берёт desktop-режим Fluent-скина как основу.
   Брейкпоинт (`700.0`, ширина *самого виджета*, не окна) выбран тем же способом, что у `structured_log_material` (список ~360 + минимально полезная панель деталей) — оба скина независимо пришли к близким числам для похожей раскладки.

3. **Категория — горизонтальный ряд pill-кнопок (`LogCategoryFilterBar`), не `CupertinoSlidingSegmentedControl`; уровень — `CupertinoSlidingSegmentedControl`.**
   `CupertinoSlidingSegmentedControl` не подходит для категории: он рассчитан на маленький фиксированный набор опций (типичный кейс в HIG — 2–5), не скроллится и не умеет расти под динамический, заранее не известный набор строк (`category` — произвольные значения из данных приложения). Уровень же — фиксированный список из пяти опций (`All`/`Debug+`/`Info+`/`Warning+`/`Error+`), что ровно подходящий случай для `CupertinoSlidingSegmentedControl`; ряд обёрнут в горизонтальный скролл на случай очень узких вьюпортов (не полагается, что все пять сегментов обязательно влезут).
   `CupertinoSlidingSegmentedControl<T>` требует non-nullable `T` (`bound Object`) — `LogLevel?` (где `null` = «All») напрямую не годится в качестве типа сегмента; представлено как индекс в списке опций (`int`), см. `cupertino_log_viewer.dart`.

4. **`logLevelColor` извлекается в `structured_log_flutter` сейчас**, а не остаётся третьей дублированной копией.
   Design.md `add-structured-log-fluent` (Decision 3) явно отложил это извлечение до появления третьего скина и зафиксировал условие: «Стоит извлечь, когда появится третий скин (`structured_log_cupertino`) — тогда дублирование станет тройным и риск разъезда вырастет». Это условие наступило. Публичный путь импорта у потребителей не меняется (`structured_log_material`/`structured_log_fluent` реэкспортируют её из своих barrel-файлов) — риска breaking change для существующих импортов нет. `logLevelAbbreviation()` (специфична для компактного бейджа `structured_log_fluent`, не нужна ни Material, ни Cupertino) не извлекается — остаётся локальной для `structured_log_fluent`.

5. **Пример-приложение таргетится на web** (`flutter create --platforms=web`), как и оба предыдущих скина, а не на реальный iOS-симулятор.
   Альтернатива — `--platforms=ios` для «настоящей» нативной Cupertino-сборки. Отклонено для CI: существующая матрица гоняется на `ubuntu-latest`, нет macOS/iOS-раннера; web-рендерер Flutter отрисовывает встроенные Cupertino-виджеты идентично независимо от хост-ОС, так что CI-проверка остаётся содержательной. Контрибьютор на macOS может локально добавить платформу `ios`/`macos` и запустить в Simulator — это не заблокировано, просто не входит в CI-проверяемый путь.

6. **Именование: `structured_log_cupertino`**, без промежуточного `_flutter` — по решению 6 из `design.md` исходной change (`structured_log_material`/`structured_log_cupertino`/`structured_log_fluent`, material/cupertino/fluent однозначно про Flutter и без уточняющего сегмента); третье и последнее имя из этого изначально зарезервированного набора.

7. **CI: расширить существующую матрицу джобы `flutter`** в [.github/workflows/ci.yml](../../.github/workflows/ci.yml) новым пакетом, а не заводить отдельную джобу/workflow — тот же принцип, что у двух предыдущих скинов.

## Risks / Trade-offs

- [Риск] Извлечение `logLevelColor` из `structured_log_material`/`structured_log_fluent` в `structured_log_flutter` задевает два уже опубликованных-в-репозитории (пусть и не на pub.dev) пакета → [Митигейшн] чисто механический рефакторинг (перемещение функции + реэкспорт из barrel-файла), публичный путь импорта consumers не меняется; оба пакета переформатированы/прогнаны через `flutter analyze`/`flutter test` после изменения.
- [Риск] Push-навигация в детали на узких экранах требует `Navigator` в дереве виджетов (в отличие от Material/Fluent-скинов, где встраиваемый виджет самодостаточен без Navigator на узких экранах — Material открывает bottom sheet через `Overlay`, тоже требующий `Navigator`, так что фактически паритет) → [Митигейшн] `CupertinoApp`/любой `MaterialApp`/`WidgetsApp`-потомок уже предоставляет `Navigator`; задокументировано в dartdoc `CupertinoLogViewer`.
- [Риск] `CupertinoSlidingSegmentedControl`'s non-nullable type parameter — источник рантайм-assert (`groupValue` не среди ключей `children`), если `levelFilter` установлен программно на значение вне пяти опций бара (например, `LogLevel.critical`/`LogLevel.trace`) → [Митигейшн] `groupValue` вычисляется как `null` (не как «отсутствующий» индекс), когда текущий `levelFilter` не входит в список опций — сегмент-контрол просто не подсвечивает ничего, без краша; покрыто тестом.
- [Риск] CI не проверяет реальную iOS-сборку → [Митигейшн] см. Decision 5 — web-таргет для example достаточен для содержательной CI-проверки; реальная iOS-сборка — ответственность контрибьютора локально, если понадобится.

## Migration Plan

1. Извлечение `logLevelColor` в `structured_log_flutter/lib/src/log_level_colors.dart` (+ тест); реэкспорт из barrel-файлов `structured_log_material`/`structured_log_fluent`, удаление/сокращение их локальных копий.
2. Скаффолдинг `structured_log_cupertino/`: `pubspec.yaml` (`flutter` sdk, `structured_log`/`structured_log_flutter` hosted, `cupertino_icons`), `lib/`, `test/`.
3. Реализация виджетов: `CupertinoLogViewer` (встраиваемый, тулбар + категория + уровень + адаптивный список/master-detail), `CupertinoLogViewerPage` (тонкая обёртка `CupertinoPageScaffold`), `LogCategoryFilterBar`, `LogEntryTile`, `LogEntryDetailPanel`, `LogViewerEmptyState`.
4. Виджет-тесты на каждый сценарий из `specs/flutter-log-viewer-cupertino/spec.md`.
5. `example/`: `flutter create --platforms=web`, демо-приложение (аналогично `structured_log_fluent/example/`, включая встроенный виджет в боковой панели с `Expanded`, не фиксированной шириной).
6. Регистрация в `melos.yaml` (`packages:` + `test:flutter` scope).
7. Расширение CI-джобы `flutter` матрицей на `structured_log_cupertino` (+ `example/`).
8. `README.md`/`README.ru.md` для нового пакета; обновление `structured_log_flutter`/`structured_log_material`/`structured_log_fluent` README (упоминание общей `logLevelColor`); обновление корневых `README.md`/`README.ru.md`/`AGENTS.md`.
9. `openspec-verify-change` перед архивацией.
10. Откат: пакет не опубликован — откат через `git revert`; извлечение `logLevelColor` — единственное изменение, задевающее существующие пакеты, тоже безопасно откатывается тем же коммитом/PR.

## Open Questions

(нет)
