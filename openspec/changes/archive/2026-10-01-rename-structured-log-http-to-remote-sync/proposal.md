## Why

`structured_log_http` называется по транспорту, а не по тому, что делает: он синхронизирует журнал приложения с удалённым `structured_log_server`. Имя ещё и сталкивается с соседями: с появлением `structured_log_http_client`, который *логирует* HTTP-вызовы приложения, два пакета с `http` в имени делают противоположное, и README обоих вынуждены начинаться с «не путать». Мейнтейнер решил провести ребрендинг пакета в `structured_log_remote_sync`.

Пакет уже опубликован на pub.dev (`0.1.0-dev.1`, `0.1.0`), поэтому переименование — это не только `git mv`: у тех, кто от него зависит, код должен продолжить собираться, а страница старого пакета — честно сказать, что он больше не развивается и куда идти.

## What Changes

- **BREAKING** (для импорта): пакет `emb/structured_log_http/` переезжает в `emb/structured_log_remote_sync/` и называется `structured_log_remote_sync`; библиотека — `package:structured_log_remote_sync/structured_log_remote_sync.dart`. Первая версия на pub.dev — `0.1.0`.
- **BREAKING** (для API): `HttpLogOutput` переименовывается в `RemoteSyncLogOutput`. `BatchSender` и `BatchResult` остаются как есть — в их имени нет ни транспорта, ни бренда. Поведение не меняется ни в чём.
- В `emb/structured_log_http/` остаётся пакет-прослойка без собственной реализации: библиотека, помеченная `@Deprecated`, реэкспортирует новый пакет и объявляет `HttpLogOutput` устаревшим `typedef` на `RemoteSyncLogOutput`; README начинается с уведомления о переименовании. Он выходит последней версией `structured_log_http` (`0.1.1` через `melos version`), после чего пакет помечается на pub.dev как discontinued с «Replaced by: `structured_log_remote_sync`» — это и есть режим «только чтение»: версии остаются скачиваемыми, пакет уходит из поиска, страница показывает баннер с новым именем.
- Ссылки на пакет по всему репозиторию — `melos.yaml`, CI, порог покрытия, `packages/e2e`, документация, сайт, README соседних пакетов, `AGENTS.md` — переводятся на новое имя.

Вне объёма: переименование капабилити `structured-log-http-sender` (OpenSpec не умеет переименовывать капабилити, а отправщик по-прежнему ходит по HTTP — имя капабилити остаётся точным); правка `CHANGELOG.md` (их пишет только `melos version`); сама публикация и пометка discontinued — действия владельца пакета на pub.dev.

## Capabilities

### Modified Capabilities

- `structured-log-http-sender`: все требования называют `RemoteSyncLogOutput` вместо `HttpLogOutput`; добавлено требование о публикации под новым именем и об устаревшей прослойке `structured_log_http`.

## Impact

- `emb/structured_log_remote_sync/` — перенесённый пакет (код, тесты, README).
- `emb/structured_log_http/` — прослойка: `pubspec.yaml`, `lib/`, тест, README/README.ru, `CHANGELOG.md` без изменений.
- `melos.yaml`, `.github/workflows/ci.yml`, `tool/coverage_floors.json`, `.dockerignore`.
- `packages/e2e` — зависимость и импорт.
- `docs/**`, `README*.md`, README соседних пакетов `emb/`, `AGENTS.md`, `site/` (оглавление пакетов и главная, генератор не трогается — он находит пакеты сам).
- Ссылки на пути в открытом `add-structured-log-server`.
