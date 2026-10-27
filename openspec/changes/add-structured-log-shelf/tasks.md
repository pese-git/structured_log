## 1. structured_log_shelf

- [x] 1.1 Сверить поведение `shelf` с исходниками и пробной программой до написания кода, на 1.4.0 и последней 1.4.x:
  - как `HijackException` проходит через `Pipeline` и `shelf_io.serve` (decision 7);
  - чем `request.requestedUri.path` отличается от `request.url` под `Router.mount` и `Cascade` (decision 5);
  - бросает ли `Response.change(headers:)` на захваченном или уже отданном ответе (decision 9);
  - доступна ли `shelf` 1.4.0 на текущем стабильном Dart (decision 11).

  Расхождения внести в `design.md` до 1.3.
- [x] 1.2 Скаффолдинг пакета `emb/structured_log_shelf/`:
  - `pubspec.yaml`: `shelf: ^1.4.0`, `structured_log: ^0.3.2+2`, `sdk: ^3.0.0`, версия `0.1.0-dev.0`, без `publish_to`;
  - `LICENSE`;
  - barrel-файл `lib/structured_log_shelf.dart`.

  `analysis_options.yaml` не заводится: его нет ни у одного пакета `emb/`.
- [x] 1.3 Middleware и `ShelfLogLevels` (`lib/src/shelf_middleware.dart`):
  - итоговые записи `http_request_handled`/`http_request_failed` и необязательная `http_request_received` (decision 1);
  - словарь полей: `method`, `path`, `status_code`, дробное `duration_ms`, `category` (decisions 2, 8);
  - уровень по исходу; `HijackException` пишется как `hijacked: true` и пробрасывается без изменений; прочие исключения пробрасываются через `rethrow` (decision 7);
  - логгер на каждом запросе через `getLogger(loggerName)`, если `logger` не передан (decision 10).
- [x] 1.4 Корреляция (decisions 3, 4):
  - логгер с `withCorrelation(requestId:)` и `request_id` в `request.context` под ключами `structured_log_shelf.*`;
  - расширение `request.logger` / `request.requestId`, бросающее `StateError` с именем middleware, если middleware не подключён;
  - `requestIdGenerator` (по умолчанию 12 hex-символов) и заголовок ответа `responseHeader` (по умолчанию `X-Request-Id`);
  - `trustIncomingRequestId`/`incomingRequestIdHeader` с проверкой `^[A-Za-z0-9._:-]{1,128}$` и `request_id_rejected: true` без отвергнутого значения.
- [x] 1.5 Маскирование и защита (decisions 5, 6, 9):
  - `query` с маскированием по `redactedQueryParameters`;
  - `logHeaders` с `request_headers`/`response_headers` и маскированием по `redactedHeaders`;
  - наборы по умолчанию — своей копией, равной `_dio`;
  - тела не пишутся, настройки для них нет;
  - `filter`, построение записи, маскирование, лог и добавление заголовка — под `try`; бросивший `filter` стоит записей, но не корреляции.
- [x] 1.6 Тесты на каждый сценарий `specs/shelf-request-logging/spec.md` (`test/shelf_middleware_test.dart`):
  - обработчик вызывается напрямую через `Request('GET', Uri.parse('http://localhost/...'))`;
  - сценарий захвата сокета — отдельной группой через `shelf_io.serve` на loopback;
  - сценарии с бросающими колбэками и sink'ом проверяют, что ответ не изменился;
  - `StructlogConfiguration` восстанавливается в `tearDown`.

  Отдельный тест закрепляет, что наборы маскирования по умолчанию равны наборам `structured_log_dio` (риск «пятая копия»). Сравнение идёт по литералам: пакет `_dio` не импортируется.
- [x] 1.7 Проверить мутацией, что тесты краснеют:
  - без `try` вокруг `filter`;
  - фильтр, отнимающий корреляцию;
  - `request.url` вместо `requestedUri`;
  - доверие входящему id без проверки;
  - запись отвергнутого id в поле;
  - `HijackException`, записанный как сбой;
  - заголовки без маскирования;
  - логгер, взятый один раз при сборке middleware;
  - тихий откат `request.logger` на логгер без корреляции.
- [x] 1.8 `example/main.dart`:
  - сервер `shelf_io` на loopback с middleware и обработчиком, пишущим через `request.logger`;
  - один успешный запрос, один 4xx и один бросивший обработчик — через `HttpClient` того же процесса;
  - вывод `jsonLineOutput`;
  - сервер закрывается в конце, чтобы прогон в CI завершался.

## 2. Workspace и CI

- [x] 2.1 `melos.yaml`: пакет в `packages:` и в скоупе `test:dart`
- [x] 2.2 CI-джоба `shelf-middleware` по форме `dio-interceptor`:
  - свой `pubspec_overrides.yaml` на `emb/structured_log`;
  - format и analyze;
  - прогон примера;
  - тесты с покрытием и порогом;
  - последним шагом — второй прогон тестов на `shelf: 1.4.0` (decision 11).
- [x] 2.3 Порог покрытия в `tool/coverage_floors.json` — чуть ниже измеренного, с записью-обоснованием по образцу
  `_added_2026_10_01`
- [ ] 2.4 CI зелёный на GitHub Actions, включая новую джобу

## 3. Документация

- [x] 3.1 `README.md`/`README.ru.md` пакета:
  - установка и место в `Pipeline` (первым, до middleware ошибок);
  - `request.logger` в обработчике и тест обработчика с middleware;
  - записи и их поля, уровни;
  - `X-Request-Id` и когда включать `trustIncomingRequestId`;
  - раздел о секретах: тела не пишутся, заголовки, query, сегменты пути через `filter`, текст исключений;
  - `duration_ms` без отдачи тела;
  - API и «Related packages».
- [x] 3.2 Строка о `structured_log_shelf` в разделе «Related packages»/«Связанные пакеты» (группа «Integrations»/«Интеграции»)
  README всех остальных живых пакетов `emb/`. Прослойка `structured_log_http` в разделе не участвует. В README адаптеров
  число во фразе «один из N адаптеров» увеличить на один.
- [x] 3.3 Корневые `README.md`/`README.ru.md` и `AGENTS.md`:
  - пакет в списке `emb/` и в «Структуре»;
  - раздел «Внутри `emb/structured_log_shelf/`»;
  - CI-джоба;
  - число пакетов, джоб и README в правиле «Related packages»;
  - список адаптеров в «Соглашениях».
- [x] 3.4 `docs/guides/embedding-guide.md`/`.ru.md`: раздел о `structured_log_shelf`. Это первый серверный адаптер, поэтому
  нужна оговорка, что он для Dart-сервера, а не для приложения. Перенумеровать последующие разделы и их якоря.
- [x] 3.5 Сайт, EN/RU: оглавление пакетов, карточка, строка таблицы интеграций, список адаптеров и диаграмма на главной.
  `npm run build` в `site/` проходит, и создаётся страница `/packages/structured_log_shelf/`.
