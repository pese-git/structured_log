## Why

`structured_log` сейчас умеет только писать записи локально (консоль, файл, ротация) — нет способа собрать логи с нескольких запущенных инстансов приложения (или с устройства пользователя) в одном месте, чтобы искать и фильтровать их централизованно. Разработчикам, которые уже используют структурированное логирование в нескольких сервисах/устройствах, для отладки продакшен-инцидентов нужен централизованный приёмник логов — без завязки на сторонний SaaS и без тяжёлой инфраструктуры (ELK и т.п.), в том же экосистеме Dart, что и остальной воркспейс.

## What Changes

- Добавить `structured_log_server/`: самостоятельный Dart HTTP-сервис (`shelf` + `shelf_router`) с батч-приёмом логов (`POST /v1/logs`), поиском/фильтрацией (`GET /v1/logs` — по `level`/`category`/`logger`/диапазону времени/correlation id/полнотекстовому `q`/произвольным `context.*`-полям), простой Bearer/API-key аутентификацией и `GET /healthz`. Хранилище — embedded `package:sqlite3` (без ORM/кодогенерации), файл на диске, WAL-режим.
- Добавить `structured_log_http/`: лёгкий клиентский пакет (`structured_log` — единственная зависимость) с `HttpLogOutput` — `OutputFunction`, отправляющий записи батчами по HTTP на `structured_log_server` с retry/backoff на сетевых ошибках и 5xx (не на 4xx), по эталонному паттерну сериализованной очереди `_SerializedAsyncOutput` из `structured_log/lib/src/async_file_output.dart`.
- Явно вне рамок этого change: server-rendered HTML/веб-UI для просмотра логов (используем чистый JSON API; интеграция существующих `structured_log_material`/`structured_log_fluent` с этим сервером как источником данных — отдельный будущий change), FTS5-полнотекстовый поиск (на MVP — `LIKE`), многопоточное/много-isolate масштабирование сервера, поддержка Windows в CI нового job'а (стартуем с `ubuntu-latest` из-за нативной зависимости `sqlite3`).

## Capabilities

### New Capabilities
- `log-server-api`: HTTP-контракт `structured_log_server` — батч-приём, query/фильтрация с пагинацией, Bearer/API-key аутентификация, health-check.
- `log-server-storage`: схема хранения записей лога в SQLite (таблица, индексы под частые фильтры, JSON1-фильтрация по произвольным `context`-полям, миграция схемы при старте).
- `structured-log-http-sender`: клиентский `HttpLogOutput` в `structured_log_http` — батчинг, сериализованная доставка, retry/backoff, `flushed` для ожидания перед выходом из процесса.

### Modified Capabilities
(нет — публичный API `structured_log` не меняется; новые пакеты подключаются к нему только через уже существующие `LogSink`/`OutputFunction`)

## Impact

- Новые пакеты в корне воркспейса: `structured_log_server/` (`lib/`, `bin/server.dart`, `test/`, `example/`) и `structured_log_http/` (`lib/`, `test/`, `example/`) — оба перечисляются в `melos.yaml` (`packages:`), оба чистый Dart (без Flutter).
- Зависимости: `structured_log_server` добавляет `shelf`, `shelf_router`, `sqlite3` — первые сторонние runtime-зависимости в воркспейсе за пределами `meta`/`fluent_ui`; `structured_log_http` зависит только от `structured_log`.
- CI ([.github/workflows/ci.yml](.github/workflows/ci.yml)): нужен новый job для этих двух Dart-пакетов (текущий `test`-job жёстко привязан к `working-directory: structured_log`, не матрица) — начиная с `ubuntu-latest` из-за нативной библиотеки sqlite3.
- Документация: `AGENTS.md` (разделы «Структура»/«CI»), корневые `README.md`/`README.ru.md` — короткое упоминание двух новых пакетов.
- Опубликованные пакеты (`structured_log`, `structured_log_flutter`, `structured_log_material`, `structured_log_fluent`) и их потребители не затрагиваются.
