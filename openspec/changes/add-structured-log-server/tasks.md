## 1. Скаффолдинг пакетов

- [ ] 1.1 Создать `structured_log_server/`: `pubspec.yaml` (зависимости `shelf`, `shelf_router`, `sqlite3`, `structured_log`), `lib/structured_log_server.dart` (barrel), `bin/`, `test/`, `example/`; `LICENSE` скопирован
- [ ] 1.2 Создать `structured_log_http/`: `pubspec.yaml` (единственная зависимость — `structured_log`), `lib/structured_log_http.dart` (barrel), `test/`, `example/`; `LICENSE` скопирован
- [ ] 1.3 Добавить оба пакета в `packages:` корневого [melos.yaml](../../melos.yaml); включить их в scope скриптов `analyze`/`format`/`format:check`/`test:dart` (оба чистый Dart, не Flutter)
- [ ] 1.4 `melos bootstrap`/`dart analyze` на пустых пакетах — убедиться, что скаффолдинг корректен и не ломает остальной воркспейс

## 2. structured_log_server — storage-слой

- [ ] 2.1 Определить интерфейс `LogStore` (`insertBatch`, `query`) в `lib/src/storage/log_store.dart`
- [ ] 2.2 Реализовать `SqliteLogStore` (`lib/src/storage/sqlite_log_store.dart`): схема `log_entries` (id/received_at/timestamp/level/event/category/logger/поля корреляции/context_json), индексы на level/timestamp/category/session_id/request_id и составной (level, timestamp), `PRAGMA journal_mode=WAL`
- [ ] 2.3 Миграция схемы при старте (идемпотентная, не теряющая существующие данные при повторном запуске) — `specs/log-server-storage`: Requirement "Миграция схемы при старте сервера"
- [ ] 2.4 Реализовать построение SQL-фильтра (`lib/src/storage/query.dart`): level/category/logger/from-to/correlation ids/полнотекстовый `LIKE` по event и context_json/`context.<key>` через `json_extract`, keyset-пагинация по `id`
- [ ] 2.5 Юнит-тесты storage-слоя на каждый сценарий из `specs/log-server-storage/spec.md`: round-trip произвольного поля context, использование индекса при фильтрации по level, независимость received_at от timestamp, фильтрация по незаранее известному ключу context, сохранность данных после рестарта, отсутствие блокировки чтения при конкурентной записи (WAL)

## 3. structured_log_server — HTTP API

- [ ] 3.1 Реализовать auth middleware (`lib/src/http/auth_middleware.dart`): проверка `Authorization: Bearer <api-key>` против списка активных ключей из `ServerConfig`, 401 при отсутствии/неверном ключе
- [ ] 3.2 Реализовать `POST /v1/logs` (`lib/src/http/routes/ingest_route.dart`): парсинг батча, валидация каждой записи (обязательные `event`/`level`, допустимое значение `level`), частичное сохранение валидных записей с отчётом об отклонённых по индексу, 413 при превышении лимита размера тела
- [ ] 3.3 Реализовать `GET /v1/logs` (`lib/src/http/routes/query_route.dart`): все query-параметры фильтрации из `specs/log-server-api`, пагинация (`limit` + курсор по `id`)
- [ ] 3.4 Реализовать `GET /healthz` (`lib/src/http/routes/health_route.dart`) без аутентификации, 200 при готовом хранилище
- [ ] 3.5 Унифицировать формат ошибок (`lib/src/errors.dart`): доменные ошибки → структурированный JSON-ответ с кодом и сообщением для 400/401/413/500
- [ ] 3.6 Собрать сервер (`lib/src/http/server.dart`): `Pipeline` + middleware (auth, error-handling) + `shelf_router` + `shelf_io.serve`
- [ ] 3.7 Юнит-тесты HTTP-слоя на каждый сценарий из `specs/log-server-api/spec.md`: успешный/частично невалидный батч, превышение лимита, авторизация (без ключа/один из нескольких ключей), health-check, фильтрация (по уровню+времени, по context, комбинация фильтров), пагинация курсором, структура ответа об ошибке

## 4. structured_log_server — CLI entrypoint

- [ ] 4.1 `ServerConfig`: host/port/список API-ключей/путь к файлу БД/лимиты батча — из аргументов командной строки и/или переменных окружения
- [ ] 4.2 `bin/server.dart`: парсинг конфигурации, запуск сервера, graceful shutdown по SIGINT/SIGTERM (закрытие `Database`)

## 5. structured_log_http — клиентский sender

- [ ] 5.1 Реализовать `HttpLogOutput` (`lib/src/http_output.dart`) по паттерну `_SerializedAsyncOutput`/`AsyncFileOutput` из `structured_log/lib/src/async_file_output.dart`: сериализованная очередь, `catchError` на каждом шаге, `flushed`
- [ ] 5.2 Батчинг: накопление записей до сконфигурированного размера батча или таймаута (что раньше), отправка `POST /v1/logs`
- [ ] 5.3 Retry с backoff на сетевых ошибках/5xx, без retry на 4xx (лог через `stderr` и прекращение попыток для этого батча)
- [ ] 5.4 Верхний предел буфера в памяти с вытеснением самых старых недоставленных записей при переполнении (лог через `stderr`)
- [ ] 5.5 Юнит-тесты `structured_log_http` на каждый сценарий из `specs/structured-log-http-sender/spec.md` (реальный shelf-сервер на порту 0 или мок): подключение как LogSink.output, неблокирующий вызов, отправка по размеру/таймауту батча, retry после временной ошибки, отсутствие retry на 401, ограничение буфера, `flushed` дожидается финального исхода всех записей

## 6. Интеграционное тестирование

- [ ] 6.1 `structured_log_server/test/integration_test.dart`: реальный `HttpServer` на порту 0, сквозной сценарий ingest → storage → query через `package:http`, включая фильтры и пагинацию
- [ ] 6.2 Ручной smoke test по сценарию из плана (`dart run bin/server.dart`, отправка через `HttpLogOutput`, `curl` с фильтрами, `curl /healthz`) — зафиксировать результат в этой задаче

## 7. CI

- [ ] 7.1 Добавить в [.github/workflows/ci.yml](../../.github/workflows/ci.yml) отдельный job для `structured_log_server`/`structured_log_http` (матрица по пакету, `dart-lang/setup-dart`, только `ubuntu-latest` — риск sqlite3 на Windows, см. `design.md`): `pub get` → `format --set-exit-if-changed` → `analyze` → `test`; существующие `test`/`flutter` job'ы не трогать
- [ ] 7.2 Прогнать на GitHub Actions, убедиться, что все job'ы зелёные

## 8. Документация и финализация

- [ ] 8.1 `README.md`/`README.ru.md` для `structured_log_server` (установка, конфигурация, запуск, HTTP-контракт) и `structured_log_http` (установка, быстрый старт с `HttpLogOutput`)
- [ ] 8.2 Обновить корневые `README.md`/`README.ru.md` и разделы «Структура»/«CI» в [AGENTS.md](../../AGENTS.md) (описание двух новых пакетов, новый CI job)
- [ ] 8.3 `openspec-verify-change`: сверить каждое требование из `specs/log-server-api`, `specs/log-server-storage`, `specs/structured-log-http-sender` с кодом и тестами, decisions из `design.md` соблюдены
