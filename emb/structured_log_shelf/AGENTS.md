# emb/structured_log_shelf — заметки для агентов

Дополняет корневой [AGENTS.md](../../AGENTS.md) (проект, команды, соглашения, версионирование, CI). Подгружается, когда работа идёт в этом каталоге; `CLAUDE.md` рядом — симлинк на этот файл.
- [lib/src/shelf_middleware.dart](lib/src/shelf_middleware.dart) —
  `structuredLogRequests()`, `ShelfLogLevels`, расширение `StructuredLogRequest` (`request.logger`/`request.requestId`),
  наборы маскирования.
- **Обобщает `requestLoggingMiddleware` сервера, но словарь у него — адаптеров `emb/`**: `http_request_handled`/
  `status_code`, как у `_dio`/`_http_client`, а не `request.completed`/`status` сервера. Поэтому сервер на пакет пока
  **не** переведён: переход переименовал бы события, которые проверяют тесты сервера
  (`server_integration_test.dart`, `diagnostics_isolation_test.dart`), — это отдельная заявка.
- **`request.logger` без middleware бросает `StateError`**, а не отдаёт логгер без корреляции: тихий откат и есть та
  ошибка подключения, ради которой пакет создан. Тест обработчика ставит middleware перед ним. Логгер и id лежат в
  `request.context` под ключами `structured_log_shelf.*` и доходят через `Router.mount` (проверено пробой).
- **`filter` убирает записи, а не корреляцию**: отфильтрованный запрос получает id, логгер и заголовок. Бросивший
  `filter` стоит записей (fail-closed), не ответа.
- **`HijackException` — не сбой**: пишется `http_request_handled` с `hijacked: true`, без статуса, и пробрасывается.
  Исключение обработчика пишется `http_request_failed` и пробрасывается `rethrow` с исходным стеком.
- **Ответ 500 на непойманное исключение уходит без `X-Request-Id`** — его строит `shelf_io` снаружи всех middleware
  (найдено прогоном примера). README советует middleware ошибок внутри; тест закрепляет, что тогда ответ получает
  заголовок и пишется `http_request_handled` с 500.
- **`path` — из `requestedUri`, а не `url`**: `url` отсчитывается от точки монтирования. `duration_ms` дробное и
  кончается на возврате `Response`, до отправки тела. Записи обработчика идут с `logger: shelf`.
- **Входящий `X-Request-Id` по умолчанию не принимается**; при `trustIncomingRequestId` — `^[A-Za-z0-9._:-]{1,128}$`,
  иначе свой id и `request_id_rejected: true` без самого значения. Тела не пишутся вовсе — настройки нет.
- Наборы маскирования — **пятая копия** правил (`_dio`/`_http_client`/`_go_router`/`_auto_route`); тест сверяет их с
  `_dio` по литералам, без импорта.
- Тесты зовут обработчик напрямую (`Request('GET', …)`), захват сокета — через `shelf_io.serve` на loopback.
  Мутацией проверены девять мест (фильтр, корреляция при фильтре, `url` вместо `requestedUri`, проверка и запись
  входящего id, захват, маскирование заголовков, логгер на сборке, тихий откат `request.logger`). Покрытие 100 %
  (94 из 94), порог 97; второй прогон CI — на `shelf: 1.4.0`.
