## Why

`structured_log` принципиально не имеет рантайм-зависимостей, кроме `meta`, поэтому не может тянуть в себя Flutter/Material ради in-app просмотрщика логов — но именно живой, фильтруемый in-app просмотрщик логов нужен Flutter-разработчикам, использующим структурированное логирование, во время отладки (посмотреть вывод `getLogger()`, не выходя из работающего приложения и не читая файл логов отдельно). Это требует отдельного Flutter-пакета, и наименьший полноценно рабочий срез — это headless слой данных плюс первый готовый UI-скин (Material 3, по уже спроектированным для этого проекта макетам).

## What Changes

- Перевести репозиторий на multi-package workspace на Melos, по образцу уже существующего у того же автора [cherrypick](https://github.com/pese-git/cherrypick): плоская раскладка (каждый пакет — отдельная директория в корне репозитория, без вложенности под `packages/`), пакеты перечислены явным списком по имени в `melos.yaml`. Существующий пакет переезжает в `structured_log/` без изменения публичного API, версии или истории CHANGELOG. **BREAKING** для тех, у кого локальный клон завязан на текущую плоскую структуру (пути меняются), хотя сам опубликованный пакет `structured_log` на pub.dev не затрагивается.
- Добавить `structured_log_flutter/`: headless Flutter-пакет без импортов виджетов Material/Cupertino/Fluent — `LogBuffer` (адаптер `OutputFunction`/`LogSink` на основе кольцевого буфера, накапливающий записи для отображения) и `LogViewerController` (`ChangeNotifier`, отдающий записи с фильтрацией по поиску/уровню/категории, пауза/возобновление, очистка), чтобы поверх него можно было построить UI под любую дизайн-систему.
- Добавить `structured_log_material/`: просмотрщик логов на Material 3 поверх `LogViewerController` — верхний app bar с полем поиска и чипами фильтра по уровню, прокручиваемый список записей, детальный вид развёрнутого JSON-контекста через bottom sheet (с копированием) и empty-state, различающий «логов ещё нет» и «нет записей по текущему фильтру» — по уже готовым Material-макетам для этого проекта.
- Явно вне рамок этого change: `structured_log_cupertino` и `structured_log_fluent` (макеты есть, реализации нет), расширение для DevTools и перехват ошибок через FlutterError/PlatformDispatcher. Это кандидаты на последующие отдельные change после проверки headless-ядра и первого скина.

## Capabilities

### New Capabilities
- `flutter-log-viewer-core`: headless слой состояния и буферизации (`LogBuffer`, `LogViewerController`) для построения живого, фильтруемого UI просмотра логов во Flutter, не привязанный ни к какой конкретной дизайн-системе.
- `flutter-log-viewer-material`: готовый к использованию просмотрщик логов на Material 3 (список, детальный вид развёрнутой записи, empty-state), построенный поверх `flutter-log-viewer-core`.
- `monorepo-workspace`: multi-package layout на Melos, позволяющий `structured_log`, `structured_log_flutter` и `structured_log_material` жить в одном репозитории с общими инструментами (скрипты lint/format/test), но независимым версионированием и CHANGELOG у каждого пакета.

### Modified Capabilities
(нет — собственное поведение и публичный API `structured_log` этим переездом не затрагиваются)

## Impact

- Структура репозитория: `git mv` существующего пакета в `structured_log/` (плоско, в корень); корневой `melos.yaml` становится манифестом workspace с явным списком пакетов (`packages: [structured_log, structured_log_flutter, structured_log_material]`), как в `cherrypick`; пути в `AGENTS.md`/`CLAUDE.md` обновляются.
- Новые пакеты: `structured_log_flutter/` и `structured_log_material/` в корне репозитория (у каждого свои pubspec, `lib/`, `test/`, `example/`).
- CI ([.github/workflows/ci.yml](.github/workflows/ci.yml)): сейчас сознательно без Flutter (`dart-lang/setup-dart`, без FVM), поскольку `structured_log` не зависит от Flutter — это меняется с добавлением `structured_log_flutter`/`structured_log_material`, так как их тестирование требует Flutter SDK. В workflow нужно добавить Flutter-джобу (или ветку матрицы), не сломав существующую Dart-only ветку для `structured_log`.
- Версионирование: каждый пакет сохраняет свою линию git-тегов `<package>-v<version>` по действующему соглашению из [AGENTS.md](AGENTS.md); `structured_log_flutter` и `structured_log_material` стартуют с `0.1.0-dev.1`.
- Опубликованный на pub.dev артефакт `structured_log` и его потребители не затрагиваются.
