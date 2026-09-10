## 1. Реструктуризация репозитория в monorepo

- [x] 1.1 `git mv` существующих `lib/`, `test/`, `example/`, `pubspec.yaml`, `pubspec.lock`, `CHANGELOG.md`, `README.md`, `README.ru.md`, `doc/` в `structured_log/` (плоско, в корень репозитория — по образцу [cherrypick](https://github.com/pese-git/cherrypick)); `LICENSE` скопирован туда же (нужен для будущей публикации на pub.dev)
- [x] 1.2 Обновить корневой `melos.yaml` на workspace-конфигурацию с явным списком пакетов (`packages: [structured_log]`, готово к расширению до `structured_log_flutter`/`structured_log_material`); скрипты переведены с одиночных `run:` на `exec:`/`steps:` по пакетам
- [x] 1.3 Обновить пути в разделе «Структура» [AGENTS.md](../../AGENTS.md), CI ([.github/workflows/ci.yml](../../.github/workflows/ci.yml) — `working-directory: structured_log`) и ссылки в README/README.ru
- [x] 1.4 `dart analyze`/`dart format --set-exit-if-changed`/`dart test` внутри `structured_log/` — подтверждено, пакет не сломан переносом (28/28 тестов). `melos bootstrap`/`melos run analyze`/`melos run test`/`melos run lint` подтверждены через `dart run melos <cmd>` (глобально активированный `melos` на этой машине падает с `Invalid kernel binary format version` — рассинхрон со снапшотом относительно текущего Dart SDK, не связан с реструктуризацией; `dart run melos` работает в обход этой проблемы). Для этого в корень добавлен `pubspec.yaml` (`publish_to: none`, только `melos` в dev-зависимостях — не член workspace, в `packages:` не входит), по образцу корневого `pubspec.yaml` в `cherrypick`

## 2. structured_log_flutter (headless-ядро)

- [x] 2.1 Скаффолдинг пакета: `pubspec.yaml` (зависимости: `flutter` sdk, `structured_log` через `path:`; `publish_to: none` пока не публикуется), `lib/structured_log_flutter.dart` (barrel-файл), `test/`, `example/` (не запускается через голый `dart run` — `package:flutter/foundation.dart` тянет `dart:ui`, доступный только через `flutter run`/`flutter test`, см. комментарий в файле); `LICENSE` скопирован
- [x] 2.2 Реализовать `LogBuffer`: кольцевой буфер ограниченной ёмкости (по умолчанию 500), `capture()` с сигнатурой `OutputFunction`, `ValueListenable<List<Map<String, dynamic>>>`
- [x] 2.3 Тесты `LogBuffer`: вытеснение старейшей записи при переполнении, обновление `ValueListenable` при захвате, подключение `capture` как `output` в `LogSink`
- [x] 2.4 Реализовать `LogViewerController` (`ChangeNotifier`): `levelFilter`, `categoryFilter`, `searchQuery`, `paused`, `visibleEntries`, `clear()`
- [x] 2.5 Тесты `LogViewerController`: фильтрация по уровню/категории/тексту поиска, поведение паузы, `clear()` очищает буфер и уведомляет слушателей — 17 тестов, все проходят через `flutter test`
- [x] 2.6 Dartdoc с примерами для публичного API (`LogBuffer`, `LogViewerController`) в стиле, принятом в `structured_log`
- [x] 2.7 Проверено: `grep` по `lib/` не находит импортов `package:flutter/material.dart`, `package:flutter/cupertino.dart`, `package:fluent_ui/fluent_ui.dart`

## 3. structured_log_material (Material-скин)

- [ ] 3.1 Скаффолдинг пакета: `pubspec.yaml` (зависимости: `flutter` sdk, `structured_log_flutter` через `path:`), `lib/`, `test/`, `example/`
- [ ] 3.2 Виджет списка записей: сортировка «новые сверху», живое обновление от `LogViewerController`
- [ ] 3.3 Строка записи: цветовой индикатор уровня, временная метка, `event`, тег `category` (если задан)
- [ ] 3.4 Верхняя панель: заголовок «Logs», поле поиска, чипы фильтра по уровню, переключатель паузы/возобновления, действие очистки — по макетам из [Log Viewer UI Concepts](https://claude.ai/code/artifact/400091b3-da51-4f73-a1fb-2ce779515de0)
- [ ] 3.5 Bottom sheet детального вида: полный контекст записи как пары ключ-значение + действие копирования
- [ ] 3.6 Empty-state с двумя вариантами: «логов ещё нет» и «нет записей по текущему фильтру» (с действием сброса)
- [ ] 3.7 Поддержка `Theme.of(context)` (светлая/тёмная); canonical-таблица цветов уровня лога — в одном месте, без дублирования
- [ ] 3.8 Виджет-тесты на каждый сценарий из `specs/flutter-log-viewer-material/spec.md`
- [ ] 3.9 `example/` — демо Flutter-приложение, подключающее `LogBuffer` к `LogSink` и встраивающее виджет списка

## 4. CI

- [ ] 4.1 Добавить Flutter-джобу/ветку в [.github/workflows/ci.yml](../../.github/workflows/ci.yml) (`flutter analyze`/`flutter test` для `structured_log_flutter` и `structured_log_material`), не сломав существующую Dart-only ветку для `structured_log`
- [ ] 4.2 Убедиться, что CI зелёный и на существующей, и на новой ветке

## 5. Документация и финализация

- [ ] 5.1 `README.md`/`README.ru.md` для `structured_log_flutter` и `structured_log_material` (установка, быстрый старт, пример подключения `LogBuffer` к `LogSink`)
- [ ] 5.2 `CHANGELOG.md` для обоих новых пакетов (`Unreleased` / `0.1.0-dev.1`) в формате Keep a Changelog
- [ ] 5.3 Прогнать `openspec-verify-change` перед архивацией этого change
