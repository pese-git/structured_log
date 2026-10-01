## 1. Перенос пакета

- [x] 1.1 `git mv emb/structured_log_http emb/structured_log_remote_sync`; `name: structured_log_remote_sync`, описание без старого имени; `version` и `CHANGELOG.md` не трогать.
- [x] 1.2 Библиотека `lib/structured_log_remote_sync.dart` вместо `lib/structured_log_http.dart`; `HttpLogOutput` → `RemoteSyncLogOutput` в коде, doc-комментариях и тестах.
- [x] 1.3 README/README.ru: новое имя, установка `structured_log_remote_sync: ^0.1.0`, строка «раньше назывался `structured_log_http`».

## 2. Прослойка structured_log_http

- [x] 2.1 `emb/structured_log_http/`: `pubspec.yaml` (версия `0.1.0` — бамп до `0.1.1` делает `melos version`), зависимость `structured_log_remote_sync: ^0.1.0`, `CHANGELOG.md` — копия прежнего без правок, `LICENSE`.
- [x] 2.2 `lib/structured_log_http.dart`: `@Deprecated` на библиотеке, реэкспорт `BatchResult`/`BatchSender`, `@Deprecated typedef HttpLogOutput = RemoteSyncLogOutput`.
- [x] 2.3 Тест: `HttpLogOutput` — это `RemoteSyncLogOutput`, создаётся и закрывается.
- [x] 2.4 README/README.ru: уведомление о переименовании первым абзацем, инструкция по переходу (две строки: зависимость и импорт, одно имя класса).

## 3. Ссылки по репозиторию

- [x] 3.1 `melos.yaml` (пакеты, скоуп `test:dart`), `tool/coverage_floors.json`, `.dockerignore`.
- [x] 3.2 `.github/workflows/ci.yml`: джоба отправщика — на `emb/structured_log_remote_sync`, плюс analyze/test прослойки.
- [x] 3.3 `packages/e2e`: зависимость, override и импорт.
- [x] 3.4 `docs/**`, корневые README, README соседних пакетов `emb/`, `AGENTS.md`, посадочные страницы сайта; ссылки на пути в `add-structured-log-server`. Ссылок там не оказалось — только упоминания путей в истории создания пакета (`1.5`, proposal), они оставлены как история. Пометки «не путать с `structured_log_http`» у `structured_log_http_client` сняты: с переименованием путать стало нечего.

## 4. Проверка

- [x] 4.1 `dart analyze`, `dart format --set-exit-if-changed`, `dart test` для обоих пакетов; `flutter analyze` для `packages/e2e`. Плюс `test/system_test.dart` из `packages/e2e` против настоящего сервера (9/9) и пакет-потребитель на старом имени: собирается, запускается, анализатор помечает импорт и `HttpLogOutput` новым именем.
- [x] 4.2 `dart pub publish --dry-run` для обоих пакетов.
- [x] 4.3 Генератор сайта и сборка сайта проходят.
- [x] 4.4 CI зелёный на всех джобах. Зелёный 26/26 на #93.

## 5. Публикация (владелец пакета)

- [x] 5.1 Опубликовать `structured_log_remote_sync`, поставить тег. Вышел как **`0.2.0`**, а не `0.1.0`: `melos version` запустили общим прогоном без ручного бампа, и `BREAKING CHANGE` коммита переименования поднял минорную. Тег `structured_log_remote_sync-v0.2.0`.
- [x] 5.2 Опубликовать прослойку `structured_log_http`. Вышла как **`0.2.0`** (не `0.1.1`) по той же причине, с зависимостью `structured_log_remote_sync: ^0.2.0` — разрешается.
- [x] 5.3 pub.dev → `structured_log_http` → Admin: Discontinued, Replaced by `structured_log_remote_sync`. Проверено через `/api/packages/<pkg>/options` (публичный `/api/packages/<pkg>` отдавал закешированное состояние): `structured_log_http` — `isDiscontinued: true`, `replacedBy: structured_log_remote_sync`; `structured_log_remote_sync` — `isDiscontinued: false` (по ошибке был помечен тоже, пометка снята до установки замены).
- [x] 5.4 Патч-релизы `structured_log_remote_sync` 0.2.1 и `structured_log_http` 0.2.1. Документация обоих пакетов (и опубликованные README на pub.dev) называла `structured_log_remote_sync: ^0.1.0`, а для `0.x` это `<0.2.0` — под опубликованную `0.2.0` констрейнт не подходит, и пользователь, сделавший как написано, получает ошибку разрешения. Исправлено на `^0.2.0` коммитами `fix(structured_log_remote_sync)`/`fix(structured_log_http)`, чтобы `melos version` вывел патч сам. Вышли как `0.2.0+1` (так `melos` бампает патч у `0.x`), опубликованы 02.10.2026.
