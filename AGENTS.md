# AGENTS.md

Инструкции для AI-агентов, работающих в этом репозитории.

## Проект

Репозиторий — multi-package workspace на Melos + FVM, пакеты сгруппированы по категориям
верхнего уровня (каждый пакет — директория `<категория>/<name>/`, перечисленная по полному
пути в [melos.yaml](melos.yaml)): [emb/](emb/) — встраиваемые в чужое приложение библиотеки
(`structured_log`, скины просмотрщика логов, `structured_log_remote_sync` и адаптеры к чужим библиотекам —
`bloc`/`riverpod`/`dio`/`http`/`go_router`/`auto_route`/`cherrypick`/`drift`/`logging`, плюс серверный `shelf`), [backend/](backend/) —
самостоятельные серверные приложения (`structured_log_server`), `frontend/` —
самостоятельные клиентские приложения с UI (`structured_log_admin_client`), `packages/` —
пакеты, не подпадающие однозначно ни под одну из трёх категорий выше (сейчас там один
`structured_log_e2e` — сквозные тесты через всю систему). Первоначально раскладка была полностью плоской, без категорий — по образцу
[cherrypick](https://github.com/pese-git/cherrypick) того же автора; категории введены при
добавлении сервера и admin-клиента
([openspec/changes/add-structured-log-server/](openspec/changes/add-structured-log-server/),
decision 23) — с появлением пакетов другой природы (сервис, приложение, а не только встраиваемая
библиотека) плоский список перестал сам по себе сообщать, что чем является.

[.fvmrc](.fvmrc) пинит Flutter SDK для локальной разработки/`melos`-команд явной
версией (`"flutter"`, сейчас `3.47.4`) — не строкой `"stable"`, чтобы версия не
«уезжала» молча при `fvm install`/`fvm use stable` без явного решения
контрибьютора. Отслеживается git'ом именно `.fvmrc`; `.fvm/` целиком в
`.gitignore`, так что лежащий там `fvm_config.json` — производный файл, а не
источник пина. **CI на пин не смотрит**: `.github/workflows/ci.yml` использует
`dart-lang/setup-dart`/`subosito/flutter-action` с каналом `stable` напрямую (без
FVM), так что CI всегда гоняется на актуальном на момент запуска `stable`-релизе.

**Пин нужно держать вплотную к тому, что на CI, и расхождение обнаруживается не
компилятором, а форматтером.** `dart format` меняет раскладку между версиями
Dart, и `--set-exit-if-changed` тогда валит CI на коде, который локально
отформатирован правильно — причём локальный и CI-шный форматтеры переписывают
файл друг за другом по кругу, из-за чего проверить формат локально становится
нечем. Так и случилось 15.09.2026: пин отставал (`3.44.9` против `3.47.4` на CI),
и один файл раздела 14 разошёлся ровно по этой причине. Поднимать пин —
`fvm use <version>` из корня, затем `fvm dart run melos bootstrap` и полный прогон
`analyze`/`format:check`/`test` по **всем** пакетам: обновление Flutter не раз
ломало `fluent_ui` (см. [заметки о `fluent_ui`](emb/structured_log_fluent/AGENTS.md)), и `flutter analyze` этого не ловит.

Семнадцать пакетов в `emb/` — шестнадцать живых и прослойка `structured_log_http`:

- [emb/structured_log/](emb/structured_log/) — структурированное логирование для Dart, вдохновлено
  Python `structlog`, без сторонних runtime-зависимостей (кроме `meta`). Опубликован на pub.dev.
  Главная библиотека не импортирует `dart:io` и собирается под web; файловые выходы — в отдельной
  `package:structured_log/io.dart`. Это и ещё две ломающие правки (UTC в `timestamp` по умолчанию,
  ленивая конфигурация логгеров `getLogger()`) вышли как `0.3.0` (02.10.2026) — заявка
  [openspec/changes/archive/2026-10-02-harden-structured-log-core/](openspec/changes/archive/2026-10-02-harden-structured-log-core/),
  основные спеки — [openspec/specs/structured-log-core/](openspec/specs/structured-log-core/spec.md) и
  [openspec/specs/remote-sync-entry-encoding/](openspec/specs/remote-sync-entry-encoding/spec.md); зависимые
  пакеты перешли на `structured_log: ^0.3.0` тем же релизом.
- [emb/structured_log_flutter/](emb/structured_log_flutter/) — headless-ядро для in-app просмотра логов
  во Flutter (`LogBuffer`, `LogViewerController`, `logLevelColor()`, однострочный выход
  `debugPrintOutput`, подписи скинов `LogViewerLabels` и необязательный делегат `LogViewerLocalizations`
  с en/ru); не зависит ни от какой конкретной дизайн-системы. Опубликован на pub.dev.
- [emb/structured_log_material/](emb/structured_log_material/) — Material 3 виджет просмотрщика логов
  поверх `structured_log_flutter`. Разрешена публикация на pub.dev (`publish_to: none` снят).
- [emb/structured_log_fluent/](emb/structured_log_fluent/) — Fluent UI (WinUI-style) виджет просмотрщика
  логов поверх `structured_log_flutter` (master-detail вместо bottom sheet). Разрешена
  публикация на pub.dev (`publish_to: none` снят).
- [emb/structured_log_cupertino/](emb/structured_log_cupertino/) — Cupertino (iOS-style) виджет
  просмотрщика логов поверх `structured_log_flutter` (pushed-экран деталей на узких экранах,
  master-detail split на широких/iPad). Разрешена публикация на pub.dev (`publish_to: none` снят).
- [emb/structured_log_remote_sync/](emb/structured_log_remote_sync/) — `RemoteSyncLogOutput`: `LogSink`-вывод,
  отправляющий записи на `structured_log_server` по HTTP (батчинг по размеру/таймауту, retry с
  backoff, ограниченный буфер с вытеснением самых старых записей, `flushed`). Единственная
  зависимость — `structured_log`; транспорт — `dart:io` `HttpClient`, без `dio`/`http`.
  Реализован (раздел 9 `tasks.md`), с билингвальным `README.md`/`README.ru.md`. **Раньше назывался
  `structured_log_http`** (опубликован под этим именем как `0.1.0`) — переименован вместе с классом
  (`HttpLogOutput` → `RemoteSyncLogOutput`), поведение не менялось
  ([openspec/changes/archive/2026-10-01-rename-structured-log-http-to-remote-sync/](openspec/changes/archive/2026-10-01-rename-structured-log-http-to-remote-sync/)).
  Под новым именем вышел как `0.2.0`, а не `0.1.0`: `melos version` запустили без ручного бампа, и
  `BREAKING CHANGE` коммита переименования поднял минорную. Для `0.x` констрейнт `^0.1.0` значит `<0.2.0`,
  поэтому документация обязана называть `^0.2.0` — `^0.1.0` под опубликованный пакет не подходит вовсе.
- [emb/structured_log_http/](emb/structured_log_http/) — **устаревшая прослойка**, а не пакет: последняя
  версия `structured_log_http` без собственного кода. Библиотека помечена `@Deprecated`, реэкспортирует
  `BatchSender`/`BatchResult` из `structured_log_remote_sync` и объявляет `HttpLogOutput` устаревшим
  `typedef` на `RemoteSyncLogOutput` — код зависящих собирается, анализатор называет новое имя. После её
  публикации пакет помечается на pub.dev discontinued с «Replaced by: `structured_log_remote_sync`».
  Новых версий не будет, развивать — `structured_log_remote_sync`.
- [emb/structured_log_bloc/](emb/structured_log_bloc/) — `StructuredLogBlocObserver`: `BlocObserver`,
  пишущий создание/события/смену состояния/ошибки/закрытие каждого блока и кубита записями
  `structured_log` с `category: 'bloc'`. Зависит от `package:bloc`, **не** от `flutter_bloc` —
  `flutter_bloc` построен поверх него и выставляет тот же `Bloc.observer`, так что пакет работает в
  Flutter-приложении как есть, а тестируется и гоняется в CI чистым `dart test`. Опубликован как пре-релиз (серия `0.1.0-dev.N`), [openspec/changes/archive/2026-10-01-add-structured-log-bloc/](openspec/changes/archive/2026-10-01-add-structured-log-bloc/), основная спека — [openspec/specs/bloc-log-observer/](openspec/specs/bloc-log-observer/spec.md).
- [emb/structured_log_dio/](emb/structured_log_dio/) — `StructuredLogDioInterceptor`: перехватчик `dio`,
  пишущий каждый запрос (`http_request`) и его итог (`http_response`/`http_error`) записями
  `structured_log` с `category: 'http'`, уровень — по статусу ответа. Заголовки и тела по умолчанию
  не пишутся; заголовки авторизации/cookie и query-параметры с токенами маскируются, а включённые
  тела — по именам полей (`redactedBodyFields`, harden-structured-log-core). Чистый Dart,
  опубликован как пре-релиз (серия `0.1.0-dev.N`),
  [openspec/changes/archive/2026-10-01-add-structured-log-dio/](openspec/changes/archive/2026-10-01-add-structured-log-dio/), основная спека — [openspec/specs/dio-log-interceptor/](openspec/specs/dio-log-interceptor/spec.md).
- [emb/structured_log_http_client/](emb/structured_log_http_client/) — `StructuredLogHttpClient`: то же для
  `package:http` — клиент-обёртка над любым `http.Client` с теми же записями, уровнями и маскированием,
  что у `structured_log_dio`. Пока отправщик назывался `structured_log_http`, этот пакет приходилось
  сопровождать пометкой «не путать»; с переименованием отправщика в `structured_log_remote_sync` она снята. Чистый Dart, опубликован как пре-релиз (серия `0.1.0-dev.N`),
  [openspec/changes/archive/2026-10-01-add-structured-log-http-client/](openspec/changes/archive/2026-10-01-add-structured-log-http-client/), основная спека — [openspec/specs/http-client-logging/](openspec/specs/http-client-logging/spec.md).
- [emb/structured_log_go_router/](emb/structured_log_go_router/) — `StructuredLogGoRouter`: пишет каждую
  навигацию `go_router` (`route_changed`: расположение, шаблон маршрута, предыдущее расположение),
  перенаправление (`route_redirected`, через обёртку `redirect`) и ошибку маршрутизации (`route_error`) с
  `category: 'navigation'`. **Flutter-пакет** (в отличие от трёх соседей выше): `go_router` тянет Flutter,
  поэтому `flutter test` и строка во Flutter-матрице CI. Опубликован как пре-релиз (серия `0.1.0-dev.N`),
  [openspec/changes/archive/2026-10-01-add-structured-log-go-router/](openspec/changes/archive/2026-10-01-add-structured-log-go-router/), основная спека — [openspec/specs/go-router-logging/](openspec/specs/go-router-logging/spec.md).
- [emb/structured_log_cherrypick/](emb/structured_log_cherrypick/) — `StructuredLogCherryPickObserver`:
  `CherryPickObserver`, пишущий работу DI-контейнера `cherrypick` (скоупы, модули, циклы, ошибки) с
  `category: 'di'`, никогда не печатая экземпляр. Обобщение наблюдателя, который раньше жил двумя
  дословными копиями — в сервере и admin-клиенте; **оба теперь берут его из пакета** — зависимостью по
  пути (`path: ../../emb/structured_log_cherrypick`), как клиент берёт `structured_log_admin_ui`: пакет лежит
  в том же репозитории, а оба потребителя — `publish_to: none`. Чистый Dart, `cherrypick` 3.x и 4.x, опубликован как пре-релиз (серия `0.1.0-dev.N`),
  [openspec/changes/archive/2026-10-01-add-structured-log-cherrypick/](openspec/changes/archive/2026-10-01-add-structured-log-cherrypick/), основная спека — [openspec/specs/cherrypick-log-observer/](openspec/specs/cherrypick-log-observer/spec.md).
- [emb/structured_log_drift/](emb/structured_log_drift/) — `StructuredLogDriftInterceptor`: `QueryInterceptor`
  drift, пишущий каждый запрос (`db_query`: вид, SQL, дробный `duration_ms`, `rows`/`affected_rows`/`insert_id`),
  пакет (`db_batch`), сбой (`db_query_failed` со стеком) и завершение транзакции с `category: 'db'`; медленный
  запрос (от 500 мс) — `warning` с `slow: true`. Значения аргументов по умолчанию не пишутся — ни в записи, ни
  в тексте ошибки. Чистый Dart, `drift: >=2.14.0 <3.0.0`, опубликован как пре-релиз (серия `0.1.0-dev.N`),
  [openspec/changes/archive/2026-10-14-add-structured-log-drift/](openspec/changes/archive/2026-10-14-add-structured-log-drift/), основная спека — [openspec/specs/drift-query-logging/](openspec/specs/drift-query-logging/spec.md).
- [emb/structured_log_logging/](emb/structured_log_logging/) — `StructuredLogLoggingBridge`: мост,
  передающий каждую запись `package:logging` (`LogRecord`) в `structured_log` — сообщение становится
  `event`, имя логгера — `logger`, уровень сопоставляется по `Level.value`, `error`/`stackTrace` — поля
  ядра, `category: 'logging'`. Нужен потому, что через `package:logging` пишет большая часть экосистемы
  (в зависимостях сервера — SMTP-клиент `mailer`), а сами по себе эти записи никуда не попадают. Чистый
  Dart, опубликован как пре-релиз (серия `0.1.0-dev.N`),
  [openspec/changes/archive/2026-10-14-add-structured-log-logging/](openspec/changes/archive/2026-10-14-add-structured-log-logging/), основная спека — [openspec/specs/logging-bridge/](openspec/specs/logging-bridge/spec.md).
- [emb/structured_log_riverpod/](emb/structured_log_riverpod/) — `StructuredLogRiverpodObserver`:
  `ProviderObserver` Riverpod, пишущий создание (`provider_added`), обновление (`provider_updated`), сбой
  (`provider_failed` со стеком) и удаление из памяти (`provider_disposed`) каждого провайдера с
  `category: 'riverpod'`. Провайдер называется своим `name`, а без имени — типом; аргумент семейства лежит в
  `provider_argument`. Зависит от `package:riverpod`, **не** от `flutter_riverpod` — как `structured_log_bloc`
  от `bloc`. **Только Riverpod 3** (`riverpod: ^3.0.0`): сигнатуры хуков 2.x другие. Чистый Dart, опубликован
  как пре-релиз (серия `0.1.0-dev.N`),
  [openspec/changes/archive/2026-10-14-add-structured-log-riverpod/](openspec/changes/archive/2026-10-14-add-structured-log-riverpod/), основная спека — [openspec/specs/riverpod-log-observer/](openspec/specs/riverpod-log-observer/spec.md).
- [emb/structured_log_auto_route/](emb/structured_log_auto_route/) — `StructuredLogAutoRouteObserver`:
  `AutoRouterObserver` (наследник `NavigatorObserver`) для `auto_route`, пишущий открытие (`route_pushed`), закрытие
  (`route_popped`), удаление мимо `pop` (`route_removed`) и переключение вкладок (`route_tab_changed`) с
  `category: 'navigation'` — той же, что у `structured_log_go_router`. Маршрут называется `route` (имя), `route_path`
  (шаблон `/user/:id`) и `location` (`/user/7?tab=1`); значения чувствительных имён маскируются в параметрах пути,
  query и во фрагменте. **Flutter-пакет** (`auto_route` тянет Flutter): `flutter test` и строка во Flutter-матрице CI.
  `auto_route: ">=10.0.0 <12.0.0"`. Опубликован как пре-релиз (серия `0.1.0-dev.N`),
  [openspec/changes/archive/2026-10-19-add-structured-log-auto-route/](openspec/changes/archive/2026-10-19-add-structured-log-auto-route/), основная спека — [openspec/specs/auto-route-logging/](openspec/specs/auto-route-logging/spec.md).
- [emb/structured_log_shelf/](emb/structured_log_shelf/) — `structuredLogRequests()`: `Middleware` для `shelf`, пишущий
  каждый запрос сервера одной записью (`http_request_handled` со `status_code`/`duration_ms` или `http_request_failed`
  со стеком; `http_request_received` — по желанию) с `category: 'http'`, и дающий обработчику `request.logger`,
  привязанный к `request_id` запроса, который возвращается в `X-Request-Id`. **Единственный серверный адаптер** —
  остальные стоят в приложении. Тела не пишутся никогда, входящий id — только явным доверием и после проверки. Чистый
  Dart, `shelf: ^1.4.0`, пока не опубликован (`0.1.0-dev.0`), заявка
  [openspec/changes/add-structured-log-shelf/](openspec/changes/add-structured-log-shelf/) открыта.

Плюс один пакет в `backend/`:

- [backend/structured_log_server/](backend/structured_log_server/) — self-hosted сервер приёма/
  хранения/поиска/живой трансляции логов (`shelf`+`shelf_router`, `drift`/SQLite по умолчанию,
  либо PostgreSQL как выбираемая оператором альтернатива — `--db-backend=postgres`,
  [openspec/changes/archive/2026-10-01-add-postgres-backend/](openspec/changes/archive/2026-10-01-add-postgres-backend/)). Реализованы
  приём и запрос логов, живой поток (SSE), группы/проекты/секретные ключи, аутентификация и RBAC,
  ограничение частоты, очистка по retention, собственное логирование и аудит (Этап 2), управление
  пользователями — создание/блокировка/удаление, без `email` — команды (группа/участники) и полная
  выдача ролей (`admin` без ограничений; `owner` группы — `owner`/`user` на неё саму и её проекты;
  `subject_type: user`/`team`) (Этап 4, разделы 4.3/5.3/5.6); не реализованы самостоятельная
  регистрация, восстановление пароля и подтверждение email — `tasks.md` в
  [openspec/changes/add-structured-log-server/](openspec/changes/add-structured-log-server/).
  Отдельно от этих этапов — опциональный, по умолчанию выключенный CORS
  (`--cors-allowed-origins`, [openspec/changes/archive/2026-10-01-add-server-cors/](openspec/changes/archive/2026-10-01-add-server-cors/)).
  `publish_to: none` — самостоятельный сервис, не библиотека для встраивания.

В `frontend/` два пакета — `structured_log_admin_ui` (раздел 23; Этап 2 добавил в кит `AdminTable` и
`AdminDateRangeField`) и `structured_log_admin_client` (разделы 11/12/13/14/22/27 — слой данных,
вход, принудительная и добровольная смена пароля, группы/проекты/секретные ключи, просмотр и поиск
логов, живая лента; разделы 20/32 Этапа 2 — экран аудита; разделы 13.1/13.3a/13.5a/27.1 Этапа 3 —
экран пользователей, блокировка проекта, урезанный UI выдачи роли. Остался 30.3, и он ждёт раздела 18).
В `packages/` — `structured_log_e2e` (сквозные тесты, см. [packages/e2e/AGENTS.md](packages/e2e/AGENTS.md)).

`structured_log_flutter`/`structured_log_material`/`structured_log_fluent`/`structured_log_cupertino`
опубликованы на pub.dev (стабильная линия `0.1.x` после серии `-dev.N`; версии и теги
`<package>-v<версия>` ставит `melos version`). Зависимость на `structured_log_flutter` в
`pubspec.yaml` трёх скинов — обычный hosted-констрейнт (`^0.1.x`; нижнюю границу поднимает `melos version` при каждом релизе ядра просмотрщика), путь к нему при локальной
разработке подставляет `melos bootstrap` через `pubspec_overrides.yaml` (генерируется, не
коммитится — см. `.gitignore`). Их `example/` остаются `publish_to: none` — демо-приложения
не публикуются. История и обоснование решений — в
[openspec/changes/archive/2026-10-01-add-structured-log-flutter/](openspec/changes/archive/2026-10-01-add-structured-log-flutter/),
[openspec/changes/archive/2026-10-01-add-structured-log-fluent/](openspec/changes/archive/2026-10-01-add-structured-log-fluent/) и
[openspec/changes/archive/2026-10-01-add-structured-log-cupertino/](openspec/changes/archive/2026-10-01-add-structured-log-cupertino/)
(`proposal.md`/`design.md`/`specs/`/`tasks.md` — по `tasks.md` можно свериться, что уже сделано).

## Структура

Верхний уровень репозитория:

- [README.md](README.md) / [README.ru.md](README.ru.md) — обзор workspace целиком, для внешних читателей.
- [emb/structured_log/](emb/structured_log/) — пакет структурированного логирования ([заметки](emb/structured_log/AGENTS.md)).
- [emb/structured_log_flutter/](emb/structured_log_flutter/) — headless-ядро просмотрщика логов ([заметки](emb/structured_log_flutter/AGENTS.md)).
- [emb/structured_log_material/](emb/structured_log_material/) — Material-скин просмотрщика логов ([заметки](emb/structured_log_material/AGENTS.md)).
- [emb/structured_log_fluent/](emb/structured_log_fluent/) — Fluent-скин просмотрщика логов ([заметки](emb/structured_log_fluent/AGENTS.md)).
- [emb/structured_log_cupertino/](emb/structured_log_cupertino/) — Cupertino-скин просмотрщика логов ([заметки](emb/structured_log_cupertino/AGENTS.md)).
- [emb/structured_log_remote_sync/](emb/structured_log_remote_sync/) — клиентский HTTP-sender логов ([заметки](emb/structured_log_remote_sync/AGENTS.md)).
- [emb/structured_log_http/](emb/structured_log_http/) — устаревшая прослойка к `structured_log_remote_sync` ([заметки](emb/structured_log_http/AGENTS.md)).
- [emb/structured_log_bloc/](emb/structured_log_bloc/) — наблюдатель `bloc`/`flutter_bloc` ([заметки](emb/structured_log_bloc/AGENTS.md)).
- [emb/structured_log_dio/](emb/structured_log_dio/) — перехватчик `dio` ([заметки](emb/structured_log_dio/AGENTS.md)).
- [emb/structured_log_http_client/](emb/structured_log_http_client/) — логирующая обёртка `http.Client` ([заметки](emb/structured_log_http_client/AGENTS.md)).
- [emb/structured_log_go_router/](emb/structured_log_go_router/) — логирование навигации `go_router` ([заметки](emb/structured_log_go_router/AGENTS.md)).
- [emb/structured_log_cherrypick/](emb/structured_log_cherrypick/) — наблюдатель DI-контейнера `cherrypick` ([заметки](emb/structured_log_cherrypick/AGENTS.md)).
- [emb/structured_log_drift/](emb/structured_log_drift/) — логирование запросов `drift` ([заметки](emb/structured_log_drift/AGENTS.md)).
- [emb/structured_log_logging/](emb/structured_log_logging/) — мост `package:logging` → `structured_log` ([заметки](emb/structured_log_logging/AGENTS.md)).
- [emb/structured_log_riverpod/](emb/structured_log_riverpod/) — наблюдатель провайдеров Riverpod ([заметки](emb/structured_log_riverpod/AGENTS.md)).
- [emb/structured_log_auto_route/](emb/structured_log_auto_route/) — наблюдатель навигации `auto_route` ([заметки](emb/structured_log_auto_route/AGENTS.md)).
- [emb/structured_log_shelf/](emb/structured_log_shelf/) — логирование запросов сервера на `shelf` ([заметки](emb/structured_log_shelf/AGENTS.md)).
- [backend/structured_log_server/](backend/structured_log_server/) — сервер логирования ([заметки](backend/structured_log_server/AGENTS.md)).
- [frontend/structured_log_admin_ui/](frontend/structured_log_admin_ui/) — библиотека UI-компонентов admin-клиента ([заметки](frontend/structured_log_admin_ui/AGENTS.md)).
- [frontend/structured_log_admin_client/](frontend/structured_log_admin_client/) — admin-клиент ([заметки](frontend/structured_log_admin_client/AGENTS.md)).
- [packages/e2e/](packages/e2e/) — `structured_log_e2e`, сквозные тесты через всю систему ([заметки](packages/e2e/AGENTS.md)).
- [melos.yaml](melos.yaml) — манифест workspace и общие скрипты (analyze/format/test/lint/build).
- [pubspec.yaml](pubspec.yaml) — корневой pubspec workspace (`publish_to: none`, не публикуется); нужен
  только для того, чтобы `fvm dart run melos <cmd>` резолвил `melos` как dev-зависимость — сам по себе
  не является пакетом workspace и не перечислен в `packages:` в `melos.yaml`.
- [openspec/](openspec/) — артефакты OpenSpec: `changes/` — открытые change-заявки
  (proposal/design/specs/tasks), `changes/archive/` — закрытые, `specs/` — основные спеки, куда
  архивация переносит дельты. `specs/` появился только с адаптерами `emb/` (2026-10-01); более
  ранние заявки (сервер, скины, пагинация и др.) так и лежат в `changes/`, и их контракт читается
  оттуда, а не из `specs/`. Открыты сейчас две — `add-structured-log-server` и `add-structured-log-shelf`. Закрытые лежат в `changes/archive/`, а их
  дельты — в `specs/`: `harden-structured-log-core` (надёжность ядра, маскирование тел в `_dio`/`_http_client`,
  кодирование записей в `_remote_sync`, `LogBuffer`) выпущена и заархивирована 02.10.2026; `add-structured-log-drift`
  (`drift-query-logging`), `add-structured-log-logging` (`logging-bridge`) и `add-structured-log-riverpod`
  (`riverpod-log-observer`) — 14.10.2026; `add-structured-log-auto-route` (`auto-route-logging`) и `add-log-viewer-labels` (подписи и
  локализация скинов, дельты в `flutter-log-viewer-*`) — 19.10.2026.
- [docs/](docs/) — сквозная (не per-package) документация дизайна: сейчас описывает систему
  `structured_log_server`/`structured_log_remote_sync`/`structured_log_admin_client`, спроектированную в
  [openspec/changes/add-structured-log-server/](openspec/changes/add-structured-log-server/) —
  читаемое по темам изложение поверх `design.md`/`specs/*.md`, а не замена им (при расхождении
  приоритет у OpenSpec-артефактов). Билингвальные пары файлов (`*.md`/`*.ru.md`), по той же
  конвенции, что `README.md`/`README.ru.md` и `emb/structured_log/doc/ARCHITECTURE.md`/`.ru.md`. См.
  [docs/README.md](docs/README.md) для оглавления. **Два способа пользоваться проектом —
  самостоятельно (`structured_log` и, по желанию, in-app просмотрщик, вообще без сервера) или
  вместе с self-hosted `structured_log_server` — названы прямо в первом абзаце
  [docs/README.md](docs/README.md)/`.ru.md`, а не выводятся из контекста**; внутри `guides/` это
  разделение проведено буквально — [guides/README.md](docs/guides/README.md)/`.ru.md` группируют
  пять руководств в три раздела («Самостоятельно», «Вместе с self-hosted сервером», «Вклад в
  репозиторий»), и [guides/embedding-guide.md](docs/guides/embedding-guide.md) — единственное
  руководство в первой группе — как добавить `structured_log` и, по желанию, in-app просмотрщик
  (`structured_log_flutter` + один из трёх скинов) в собственное приложение вообще без сервера;
  `structured_log_remote_sync` там тоже упомянут, но кратко, с отсылкой на `developer-guide.md` за
  деталями серверной стороны. Добавлено, когда выяснилось, что у `emb/`-пакетов не было отдельной
  инструкции по внедрению внутри `docs/` (decision, 22.09.2026) и затем явно усилено по прямому
  запросу — донести дуальность «сам по себе / вместе с сервером» лаконично на главной странице
  сайта и полно в разделах документации (decision, 22.09.2026); соответствующие разделы
  `developer-guide.md`/`.ru.md` теперь ссылаются на `embedding-guide.md`, а не дублируют
  установку/quick start каждого пакета.
- [site/](site/) — сайт проекта на Astro + Starlight, билингвальный (English/Русский):
  просматриваемая, с поиском версия [docs/](docs/) плюс страница на каждый пакет
  [emb/](emb/) (`/packages/<пакет>/` — установка/quick start/API из его README, раздел
  добавлен, когда выяснилось, что у встраиваемых библиотек на сайте не было вообще никакой
  документации по использованию). Главная страница (`index.mdx`/`ru/index.mdx`) прямо на виду
  отражает ту же дуальность, что и `docs/README.md`: вступительный абзац называет оба режима, а
  «Quick start» — это `<Tabs>` (Starlight) с двумя вкладками, «Standalone, no server» и «With the
  self-hosted server», вместо одного линейного пути через сервер; карточки пакетов ниже —
  два `<CardGrid>`, один на каждый режим, а не одна общая сетка. Самостоятельный npm-проект вне
  Melos workspace, не перечислен в `melos.yaml`. Контент **генерируется** скриптом
  ([site/scripts/migrate_docs.py](site/scripts/migrate_docs.py)) из `docs/**/*.md`/`*.ru.md`
  и `emb/<пакет>/README(.ru).md`, а не пишется вручную — правки вносятся в источник, затем
  скрипт перегенерирует `site/src/content/docs/`. Ссылки, ведущие за пределы переносимого
  источника (на `openspec/`, исходники других пакетов, `AGENTS.md`, example-приложение),
  скрипт переписывает на `github.com/pese-git/structured_log`. Главная страница
  (`index.mdx`/`ru/index.mdx`), оглавление пакетов (`packages/index.md`/`ru/packages/index.md`)
  и `astro.config.mjs` — вручную, скриптом не трогаются (`PROTECTED` в самом скрипте — и
  `site/.gitignore`'s исключения для `src/content/docs/` держатся в синхроне с этим списком
  вручную, не выводятся автоматически). Mermaid-диаграммы архитектурных страниц рендерятся на
  клиенте (`astro-mermaid`), без build-time Chromium. См. [site/README.md](site/README.md).
- [deploy/](deploy/) — самостоятельное развёртывание через docker-compose: сервер и admin-клиент за одним
  nginx ([заметки](deploy/AGENTS.md)).
- [.github/workflows/ci.yml](.github/workflows/ci.yml) — CI.
- [LICENSE](LICENSE) — лицензия репозитория; копия лежит также внутри `emb/structured_log/`
  (и будет копироваться в каждый новый пакет), так как `dart pub publish` пакует только
  содержимое директории пакета.

## Заметки по каталогам

Подробности о каждом пакете и приложении лежат в `AGENTS.md` его каталога (`CLAUDE.md` рядом — симлинк на него). Файл каталога подгружается, когда работа идёт внутри него, поэтому в корневом файле остаются только правила, общие для всего репозитория. Ссылки на файлы каталогов — в списке «Верхний уровень репозитория» выше.

**Новый каталог с собственным `AGENTS.md` — это и `CLAUDE.md` рядом (симлинк на него: `ln -s AGENTS.md CLAUDE.md`), и, для пакета `emb/`, файл `.pubignore` с двумя строками `AGENTS.md` и `CLAUDE.md`.** Без `.pubignore` заметки уедут в архив на pub.dev: `dart pub publish` берёт всё, что не в `.gitignore`, а симлинк раскрывает в обычный файл. `.pubignore` в каталоге заменяет только `.gitignore` этого же каталога, а правила из корневого (lock-файлы, `pubspec_overrides.yaml`, `coverage/`) остаются в силе; это проверено листингом `dart pub publish --dry-run` для всех пакетов `emb/`. Заметки каталога дополняют этот файл, а не повторяют его: общее (команды, соглашения, версионирование, CI) живёт здесь.

## Команды

Локально SDK вызывается **только через FVM** (`fvm dart …`, `fvm flutter …`) — на версии из
[.fvmrc](.fvmrc); глобальный SDK может отличаться, и тогда `format:check` расходится с CI (см. выше).
Melos запускается из корня репозитория как `fvm dart run melos <cmd>` — корневой
[pubspec.yaml](pubspec.yaml) держит `melos` в dev-зависимостях, а `sdkPath` в [melos.yaml](melos.yaml)
указывает на FVM-SDK, так что скрипты внутри тоже идут на закреплённой версии. Глобально
активированный `melos` не используйте: его снапшот привязан к той версии Dart, под которой его ставили.
Скрипты, кроме `clean`, определены через `exec:`/`steps:` и выполняются в директории каждого пакета
workspace:

```bash
fvm dart run melos bootstrap
fvm dart run melos run analyze
fvm dart run melos run test
fvm dart run melos run lint
```

Для прямых вызовов нужно сначала зайти в директорию пакета (Flutter-пакеты — `fvm flutter analyze`/`fvm flutter test`):

```bash
cd emb/structured_log

fvm dart analyze
fvm dart format .
fvm dart format --set-exit-if-changed .   # format:check
fvm dart test
fvm dart test --coverage=coverage
fvm dart run example/main.dart
```

`melos run lint` запускает analyze + format:check вместе; `melos run build` — `pub get` + analyze;
`melos run example` — пример конкретно для `structured_log` (все — через `fvm dart run melos run …`).

## Соглашения

- Публичный API `structured_log` экспортируется только через [emb/structured_log/lib/structured_log.dart](emb/structured_log/lib/structured_log.dart); новые публичные символы добавлять туда же. Исключение — то, что требует `dart:io`: оно идёт в [emb/structured_log/lib/io.dart](emb/structured_log/lib/io.dart), а главная библиотека остаётся без `dart:io` (стережёт `test/io_test.dart`).
- `BoundLogger.bind()` / `unbind()` иммутабельны — всегда возвращают новый экземпляр, никогда не мутируют `_context` на месте.
- Процессоры имеют тип `Map<String, dynamic>? Function(Map<String, dynamic> entry)`; возврат `null` отбрасывает запись. Новые процессоры должны быть чистыми функциями и не зависеть от порядка выполнения, если это не документировано отдельно.
- `StructlogConfiguration` — глобальное изменяемое состояние (`_current`); тесты, вызывающие `configure()`, обязаны делать `reset()` в `tearDown`, чтобы не влиять на другие тесты.
- Никаких сторонних runtime-зависимостей у `structured_log` — сохранять это, если явно не попросили иначе. Остальные пакеты `emb/` этому ограничению не подчиняются: Flutter-пакеты (`structured_log_flutter`/`structured_log_material`/`structured_log_fluent`/`structured_log_cupertino`) и адаптеры, для которых чужая библиотека и есть смысл пакета (`structured_log_bloc` → `bloc`, `structured_log_dio` → `dio`, `structured_log_http_client` → `http`, `structured_log_go_router` → `go_router`, `structured_log_cherrypick` → `cherrypick`, `structured_log_drift` → `drift`, `structured_log_logging` → `logging`, `structured_log_riverpod` → `riverpod`, `structured_log_auto_route` → `auto_route`, `structured_log_shelf` → `shelf`; ровно одна такая зависимость плюс `structured_log`), но `structured_log_flutter` сам не должен зависеть от конкретной дизайн-системы (Material/Cupertino/Fluent) — см. design.md в [openspec/changes/archive/2026-10-01-add-structured-log-flutter/](openspec/changes/archive/2026-10-01-add-structured-log-flutter/).
- Форматирование должно строго соответствовать существующему (`fvm dart format .` перед завершением любого изменения).
- У каждого живого пакета `emb/` в `README.md`/`README.ru.md` перед «License»/«Лицензия» есть раздел
  «Related packages»/«Связанные пакеты»: остальные пакеты семейства, сгруппированные (ядро, просмотрщик,
  доставка на сервер, интеграции), без самого пакета. Ссылки — **абсолютные на pub.dev**, а не `../<пакет>`:
  относительную генератор сайта переписал бы правильно, но pub.dev разрешает её от корня репозитория, и в
  подкаталоге `emb/` она битая. **Новый пакет `emb/` добавляется в этот раздел всех остальных README** (32 файла
  на 16 пакетов); прослойка `structured_log_http` в разделе не участвует — она discontinued.
- Артефакты OpenSpec ([openspec/changes/](openspec/changes/)) пишутся на русском языке — кроме ключевых слов
  и идентификаторов (заголовки секций типа `## Why`/`## What Changes`, имена пакетов/капабилити,
  имена символов кода, флаги команд и т.п., которые остаются как есть, не переводятся).

## Новый пакет `emb/` — чек-лист

Нужен постоянно, а правки разбросаны по ~20 местам и три из них с ручными счётчиками. Образец — последние адаптеры (`structured_log_auto_route` — Flutter, `structured_log_shelf` — чистый Dart): их коммиты показывают состав. Порядок важен: сначала проба, потом код, документация — после API.

1. **Проба и заявка.** Для адаптера к чужой библиотеке — пробная программа на нижней и верхней границе констрейнта до `design.md`: что библиотека сообщает на самом деле, а не что написано в документации (так найдены `didUnmountProvider`, `RouteData.queryParams`, `parameters:` в `SqliteException`). Заявка `openspec/changes/add-structured-log-<lib>/` на русском (`proposal`/`design`/`specs`/`tasks`), `openspec validate <имя> --strict`; реализация — по `tasks.md`, задачи отмечаются по ходу.
2. **Каталог `emb/structured_log_<lib>/`.** `lib/` (barrel + `src/`), `test/`, `example/main.dart`, `LICENSE` (копия из `emb/structured_log/`), `README.md` + `README.ru.md`, `pubspec.yaml`: версия `0.1.0-dev.0`, `homepage`/`documentation`/`repository` как у соседей, `topics` (до пяти, строчные, через дефис), `description` 60–180 символов, ровно одна чужая зависимость плюс `structured_log`, **без** `resolution:` и `publish_to`. Не создавать `CHANGELOG.md`.
3. **Заметки каталога.** `AGENTS.md` пакета (что библиотека делает на самом деле, ловушки, чем проверено мутацией), симлинк `CLAUDE.md` (`ln -s AGENTS.md CLAUDE.md`) и `.pubignore` с строками `AGENTS.md` и `CLAUDE.md` — иначе заметки уедут на pub.dev.
4. **Workspace.** `melos.yaml`: путь в `packages:` **и** имя пакета в скоупе `test:dart` или `test:flutter` (Flutter-пакет — только второй).
5. **CI.** Чистый Dart — отдельная джоба по образцу ближайшей (`bloc-observer`, `drift-interceptor`, `shelf-middleware`); Flutter — строка матрицы `flutter` (`package` + `name`). Прогон на нижней границе констрейнта — последним шагом, после проверки покрытия (ей нужен `package_config.json` первого прогона). Порог в `tool/coverage_floors.json`: чуть ниже измеренного, плюс запись `_added_<дата>`. Для отдельной джобы — пересчитать «N джоб» в разделе «CI» этого файла и добавить пункт; для строки матрицы — дописать пакет в перечисление джобы `flutter`.
6. **README семейства.** Строка нового пакета в «Related packages»/«Связанные пакеты» **всех остальных** живых пакетов, обе языковые версии (группа «Integrations»/«Интеграции»). Фраза «one of N adapters»/«один из N адаптеров» есть в README адаптеров — увеличить во всех. Сверка: `grep -L structured_log_<lib> emb/*/README.md emb/*/README.ru.md` должна назвать только два README прослойки `structured_log_http` (README самого пакета своё имя содержит).
7. **Корневые README** (`README.md` + `README.ru.md`): вступительный абзац со списком адаптеров, таблица «библиотека → что пишется → категория», диаграмма (`mermaid`), таблица пакетов (бейдж pub.dev; пока не опубликован — «not yet published»/«ещё не опубликован»).
8. **Руководство** `docs/guides/embedding-guide(.ru).md`: новый раздел (для навигации у `go_router`/`auto_route` — подраздел общего раздела), перенумерация следующих разделов и якорей, строка в оглавлении вверху и в «Where to go next».
9. **Сайт.** Вручную: `site/src/content/docs/index.mdx` и `ru/index.mdx` (абзац, таблица, диаграмма, `<Card>`), `packages/index.md` и `ru/packages/index.md` (строка). Страница `/packages/<пакет>/` генерируется из README сама. Проверка: `cd site && npm ci && npm run build`.
10. **Этот файл.** Вступительный абзац («адаптеры к чужим…»), «Проект» (число пакетов словами и пункт с описанием), «Структура» (пункт со ссылкой на `AGENTS.md` каталога), «Соглашения» (соответствие пакет → чужая библиотека; число README-файлов в правиле про «Related packages»), «CI», «Перед завершением» (список README).
11. **Перед PR.** Форматирование, анализ, тесты, прогон на нижней границе, покрытие против порога, мутации (в `AGENTS.md` пакета — какие места проверены); `dart pub publish --dry-run` в каталоге пакета: в списке нет `AGENTS.md`/`CLAUDE.md`, из замечаний — только про `pubspec_overrides.yaml`.
12. **Коммиты и слияние.** Отдельные коммиты `feat(<пакет>)`, `ci(<пакет>)`, `docs(<пакет>)`, затем `docs:` на общие файлы. **Вливать rebase'ом, не squash'ем**: правка README у всех пакетов в одном squash-коммите даёт каждому `feat`, и `melos version` поднимет минорную у всех.
13. **После слияния.** Архив заявки (`openspec archive <имя> --yes`, затем заполнить `Purpose`, поправить ссылки и абзац об открытых заявках в этом файле) → `melos version` (у нового пакета нет тега, он считает всю историю каталога: `0.1.0-dev.0` → `0.1.0-dev.1`) → push с тегами → `melos publish --dry-run` → публикация по уровням (ядро → пакеты на ядре → скины и прослойка) → «not yet published» заменить на бейдж в корневых README и на карточке сайта → пересобрать и выкатить сайт: страница пакета появляется только после выкатки.

## Коммиты и версионирование

- Сообщения коммитов пишутся в формате [Conventional Commits](https://www.conventionalcommits.org/)
  (`feat:`, `fix:`, `docs:`, `chore:`, `refactor:`, `perf:`, `test:`, `build:`, `ci:`, `revert:`;
  ломающее изменение — `!` после типа или футер `BREAKING CHANGE:`). Это нужно, чтобы
  `melos version` мог автоматически определять нужный semver-бамп по истории коммитов.
- `melos version` ищет точку отсчёта по git-тегу вида `<package>-v<version>`
  (например, `structured_log-v0.2.0-dev.1`) и версионирует только коммиты после него —
  без такого тега или без Conventional Commits в истории он не находит, что версионировать.
- `melos version -V <package>:<major|patch|minor|build|exactVersion>` — ручной бамп версии.
  **Важно:** флаги `--no-git-commit-version`/`--no-git-tag-version` НЕ делают команду
  dry-run — файлы (`pubspec.yaml`, `CHANGELOG.md`) переписываются на диске в любом случае.
- **`CHANGELOG.md` вручную не редактировать никогда** — ни для добавления записей о
  новой фиче/фиксе, ни для «уборки» после `melos version` (даже если он переписал файл
  в своём собственном формате поверх предыдущего содержимого). Версию и changelog меняет
  только `melos version` — это осознанное решение мейнтейнера, не пробел в процессе.
- Каждый пакет workspace версионируется независимо — своя линия git-тегов, свой `CHANGELOG.md`.

## CI

[.github/workflows/ci.yml](.github/workflows/ci.yml) запускается на push/PR
в `master`/`develop` и на `workflow_dispatch`, восемнадцать джоб:

- `test` — для `structured_log`: `dart format --set-exit-if-changed`, `dart analyze`,
  `dart test`, `dart run example/main.dart` — на `ubuntu-latest`/`macos-latest`/`windows-latest`
  (важно именно на всех трёх, т.к. `async_file_output.dart` и ротация делают реальные
  rename/delete/exists на файловой системе, а её поведение отличается между POSIX и Windows).
  Использует `dart-lang/setup-dart` (канал `stable`), а не FVM/Flutter — `structured_log`
  не зависит от Flutter.
- `server` — для `backend/structured_log_server/`: `dart pub get`, `build_runner`,
  `dart format --set-exit-if-changed`, `dart analyze`, `dart test
  --exclude-tags integration --exclude-tags postgres`, затем отдельным шагом
  `dart test --tags integration` (поднимает `bin/server.dart` процессом; тег
  объявлен в `dart_test.yaml`, но не исключён — разделение нужно только чтобы
  в логе было видно, какой из прогонов упал), затем `dart test --tags
  postgres --concurrency=1` против сервис-контейнера `postgres:16-alpine`
  (health check `pg_isready`, раннер сам не пускает шаги до готовности —
  ручного wait-loop, в отличие от `chromedriver` ниже, не нужно; тег
  диалект-чувствителен, `--concurrency=1` обязателен — Postgres-тегированные
  файлы делят одну физическую базу без пер-файловой изоляции и портят друг
  другу фикстуры на дефолтной параллельности, см.
  [openspec/changes/archive/2026-10-01-add-postgres-backend/](openspec/changes/archive/2026-10-01-add-postgres-backend/)) —
  только
  `ubuntu-latest` (сервис самохостится на Linux, ОС-чувствительной ротации
  файлов у него нет). `dart-lang/setup-dart` (канал `stable`), без FVM.
  Кодогенерация **обязана** идти до `analyze`/`test` — без неё пакет не
  компилируется (`*.g.dart` не коммитятся). `melos bootstrap` в CI не
  используется (`sdkPath` в `melos.yaml` указывает на FVM-SDK, которого в CI
  нет) — вместо него джоба сама пишет `pubspec_overrides.yaml` с путём на
  `emb/structured_log`, иначе pub взял бы опубликованную версию и ломающее
  изменение в core-пакете в том же PR прошло бы незамеченным.
- `e2e` — для [packages/e2e/](packages/e2e/): `flutter pub get`, кодогенерация
  **двух** пакетов (сервера и admin-клиента) и `flutter test`. Отдельной джобой
  именно поэтому: это единственный прогон, которому одновременно нужны
  сгенерированный код двух пакетов и Flutter SDK, и он поднимает `bin/server.dart`
  настоящим процессом. Перед кодогенерацией сервера джоба пишет ему
  `pubspec_overrides.yaml` на `emb/structured_log`: процесс сервера разрешает
  **свои** зависимости, и `dependency_overrides` из `packages/e2e/pubspec.yaml` до
  него не доходят — без этого он собирался против опубликованного ядра, и перенос
  файловых выходов в `io.dart` уронил всю джобу. Покрытием не инструментируется — сервер работает
  отдельным процессом, чьё покрытие сборщик не видит (см. `site`-абзац ниже
  и `tool/coverage_floors.json`).
- `remote-sync` (до переименования пакета — `http-sender`) — для `emb/structured_log_remote_sync/`: `dart pub get`,
  `dart format --set-exit-if-changed`, `dart analyze`, `dart test` — отдельной
  джобой, а не матричной записью рядом с сервером: пакет чистый Dart без
  кодогенерации, и матрица тянула бы за собой шаг `build_runner` впустую.
  Как и джоба сервера, сама пишет `pubspec_overrides.yaml` на
  `emb/structured_log`. Последними шагами проверяет прослойку `emb/structured_log_http/`
  (format/analyze/test, без порога покрытия) с overrides на оба пакета рабочей копии.
- `bloc-observer` — для `emb/structured_log_bloc/`: та же форма, что `remote-sync`
  (`setup-dart`, свой `pubspec_overrides.yaml` на `emb/structured_log`, format/analyze/тесты с
  покрытием), плюс прогон `dart run example/main.dart`. Чистый Dart — в Flutter-матрицу не входит.
- `dio-interceptor` — для `emb/structured_log_dio/`, та же форма, что `bloc-observer`.
- `http-client` — для `emb/structured_log_http_client/`, та же форма.
- `cherrypick-observer` — для `emb/structured_log_cherrypick/`, та же форма плюс второй прогон тестов на
  `cherrypick` 4.x.
- `drift-interceptor` — для `emb/structured_log_drift/`, та же форма плюс второй прогон тестов на `drift: 2.14.0`
  — нижней границе констрейнта, где появился `QueryInterceptor`.
- `logging-bridge` — для `emb/structured_log_logging/`, та же форма плюс второй прогон тестов на `logging: 1.2.0`
  — нижней границе констрейнта, чтобы она была проверена, а не предположена.
- `riverpod-observer` — для `emb/structured_log_riverpod/`, та же форма плюс второй прогон тестов на `riverpod: 3.0.0`
  — нижней границе констрейнта; без `didUnmountProvider` один тест пропускается, а парный ему идёт.
- `shelf-middleware` — для `emb/structured_log_shelf/`, та же форма плюс второй прогон тестов на `shelf: 1.4.0`
  — нижней границе констрейнта.
- `browser-cookie` — единственная джоба, которая видит, что делает с
  refresh-cookie **браузер**: настоящий `bin/server.dart`, собранный
  `lib/main.dart` (не тестовый entry point) и крошечный прокси, ставящий
  их на один origin, плюс Chrome под puppeteer-core
  (`frontend/structured_log_admin_client/tool/browser-e2e/`). Все три
  остальных слоя тут заканчиваются: `flutter test` и `packages/e2e` идут
  там, где cookie никто не хранит, а `admin-client-flow` идёт в браузере,
  но мокает сеть **ниже dio**, так что `Set-Cookie` до него не доходит.
  `http://localhost` тут несущий: браузеры считают его доверенным
  контекстом, и `Secure`-cookie принимается без сертификата. Ловушки
  вождения — в `tool/browser-e2e/README.md`; главная в том, что ввод здесь
  **противоположен** скриншотному харнессу (семантика включается после
  старта, поэтому работают настоящие нажатия, а подстановка значения —
  нет). Гонка двух вкладок воспроизводится не надеждой, а удержанием
  ответов (`holdTokenGrants`) — без этого проверка проходила и со снятой
  блокировкой.
- `admin-client-flow` — браузерный прогон пути оператора для
  `frontend/structured_log_admin_client`: `flutter pub get`, `build_runner`,
  поднятие `chromedriver` на 4444 (ждёт, пока тот ответит, иначе следующий шаг
  гонится с ещё не занятым портом), затем `flutter drive` по
  `integration_test/user_flow_test.dart`. Отдельной джобой, а не строкой
  матрицы ниже: это **не** `flutter test` — тот биндинг подменяет ввод и
  отвечает 400 на любой HTTP, и дефект, который эта джоба стережёт (диалог,
  закрывавший себя дважды и уносивший единственный показ секретного ключа),
  под ним не воспроизводится вовсе. `-d web-server`, **не** `-d chrome`: со
  вторым Flutter поднимает браузер сам, драйвер не получает WebDriver-сессию и
  прогон висит, ничего не сообщая. Headless — по умолчанию для этой команды.
- `site` — сборка сайта: `npm ci` + `npm run build` в [site/](site/) на Node 22,
  без Dart/Flutter вовсе (Astro-проект вне Melos-workspace). Проверяется
  именно «производит ли `docs/` сайт, который собирается», а не «актуален ли
  закоммиченный вывод»: вывода в репозитории нет, `src/content/docs/` (кроме
  двух посадочных страниц) генерируется хуком `prebuild` из
  `scripts/migrate_docs.py`. Значит правка в `docs/**` может уронить эту джобу,
  не тронув ни строчки Dart: падает либо сам генератор на том, чего не ожидал,
  либо сборка Astro на том, что он произвёл. **Ссылки при этом не проверяются**
  — валидатора в `astro.config.mjs` нет, так что битая ссылка внутри `docs/`
  проходит и CI, и эту джобу молча.
- `flutter` — для Flutter-пакетов (`structured_log_flutter`, `structured_log_material`
  (+`example/`), `structured_log_fluent` (+`example/`), `structured_log_cupertino`
  (+`example/`), `structured_log_go_router`, `structured_log_auto_route`, `structured_log_admin_ui`
  (+`example/`), `structured_log_admin_client`), по одному
  матричному прогону на пакет: `flutter pub get`, `dart format --set-exit-if-changed`,
  `flutter analyze`, `flutter test`. Перед `pub get` джоба пишет `pubspec_overrides.yaml` на рабочие копии
  `emb/structured_log` и `emb/structured_log_flutter` — каждому пакету матрицы, который от них зависит, путь
  отсчитывается от самого пакета (`realpath --relative-to`). Раньше матрица этого не делала, и до
  `harden-structured-log-core` разницы не было; но `structured_log_flutter`, опирающийся на `formatLogfmt` из ещё
  не выпущенного ядра, против опубликованного `0.2.2+1` не компилируется вовсе. Для `structured_log_admin_client` между `pub get` и
  `format` вставлен условный (`if: matrix.package == ...`) шаг `build_runner` — кодогенерация нужна
  только ему.
  Для `structured_log_auto_route` последним шагом идёт второй прогон тестов на `auto_route: 10.0.0` (нижняя граница
  констрейнта; шаг дописывает override в `pubspec_overrides.yaml` и повторяет `pub get`/`flutter test`).
  Только `ubuntu-latest` — этим пакетам не нужна ОС-чувствительная проверка ротации файлов.
  Использует `subosito/flutter-action`, канал `stable`.
- `shell` — `shellcheck` по трём скриптам развёртывания (`deploy/deploy.sh` и
  два в `deploy/k8s/`). Они не Dart, поэтому ни одна другая джоба на них не
  смотрит, и ни один тест их не запускает: ошибка ждёт того, кто будет
  разворачивать следующим. Ловится класс, который читатель проскакивает
  глазами — неэкранированная подстановка, разъезжающаяся на пути с пробелом,
  опечатка в имени переменной, `[`-проверка со смыслом, отличным от прочтения.
  **Не ловится** логика и — это стоит сказать, потому что ровно из-за этого
  джобу и предложили, — ошибка в *другой* оболочке: `"$repo:latest"`, набранное
  в интерактивном zsh, где `:l` это модификатор нижнего регистра, для `bash`
  совершенно корректно. Все три скрипта объявляют `#!/usr/bin/env bash` и
  запускаются как bash. Уровень строгости — по умолчанию, то есть валит любое
  замечание; сегодня все три чисты, так что наследия, которое пришлось бы
  прощать, нет, и первое же замечание будет о том, что кто-то только что внёс.
- `tools` — корень workspace: `dart pub get`, `format`, `analyze` и `dart test` по
  `tool/` и `test/`. Корень не публикуется и кода почти не держит, но один файл в нём
  есть — [tool/coverage_floor.dart](tool/coverage_floor.dart), гейт покрытия, который
  зовут остальные джобы. Он решает, проходит ли сборка, поэтому проверяется так же, как
  пакеты, которые он судит.

**Покрытие меряется и валит сборку по порогу на пакет**
([tool/coverage_floors.json](tool/coverage_floors.json)). Порог — не цель, а нижняя
граница, поставленная чуть ниже измеренного на момент ввода гейта; поднимать её, когда
пакет этого заслужил, нормально, опускать ради зелёной сборки — то, что этот файл и
делает заметным. Числа на пакет, а не одно на репозиторий: у кита виджетов и у сервера
процент означает разное, и общий порог удовлетворяли бы те, кому он нужен меньше всех.

Три вещи, без которых число врёт, и все три проверены измерением:

- **Генерация не считается.** Иначе сервер читается как 53,4 % вместо 91,1 %: один
  `database.g.dart` — 4578 строк drift-кода — весит больше всего рукописного вместе.
  Исключаются `*.g.dart`, `*.freezed.dart` и `app_localizations*` — последнее потому,
  что вывод `gen-l10n` **коммитится**, под первые два шаблона не подпадает и в одном
  admin-клиенте добавляет 503 строки, двигая его число на шесть пунктов.
- **У сервера складываются два прогона из трёх** — дефолтный и `postgres`: они
  покрывают разные половины `storage/database.dart`. `format_coverage` читает один
  каталог за раз, поэтому отчёты рендерятся отдельно и склеиваются; файл, измеренный
  обоими, приезжает дважды, и гейт сливает его построчно.
- **Прогон `integration` не инструментируется.** Он запускает `bin/server.dart`
  **отдельным процессом**, покрытия которого сборщик не видит: весь набор даёт 1,4 %
  против 91,1 % у юнитов. Плюс под `--coverage` два из четырнадцати его тестов упали
  однажды и прошли на следующем прогоне — флак, купленный ни за что.

## Перед завершением изменения

Команды — через FVM, в директории затронутого пакета (Flutter-пакеты — `fvm flutter analyze`/`fvm flutter test`):

1. `fvm dart analyze` — не должно быть замечаний.
2. `fvm dart test` — все тесты должны проходить. **Для `structured_log_server` нужен кейс под
   тегом `postgres`, если изменение трогает запрос к БД, собранный чем-то сложнее
   `equals`/`isNull`/`isIn`, — или опирается на измеренное поведение SQLite, даже когда
   запроса не трогает вовсе.** Прогон по умолчанию идёт на SQLite (`NativeDatabase.memory()`),
   и зелёный он потому, что PostgreSQL никто не спросил (см. два пункта про диалекты в
   разделе о сервере).
3. `fvm dart format --set-exit-if-changed .` — код должен быть отформатирован.
4. При изменении публичного поведения пакета обновлять его `README.md`/`README.ru.md`
   ([emb/structured_log/](emb/structured_log/README.md), [emb/structured_log_flutter/](emb/structured_log_flutter/README.md),
   [emb/structured_log_material/](emb/structured_log_material/README.md), [emb/structured_log_fluent/](emb/structured_log_fluent/README.md),
   [emb/structured_log_cupertino/](emb/structured_log_cupertino/README.md),
   [emb/structured_log_bloc/](emb/structured_log_bloc/README.md),
   [emb/structured_log_dio/](emb/structured_log_dio/README.md),
   [emb/structured_log_http_client/](emb/structured_log_http_client/README.md),
   [emb/structured_log_go_router/](emb/structured_log_go_router/README.md),
   [emb/structured_log_cherrypick/](emb/structured_log_cherrypick/README.md),
   [emb/structured_log_drift/](emb/structured_log_drift/README.md),
   [emb/structured_log_logging/](emb/structured_log_logging/README.md),
   [emb/structured_log_riverpod/](emb/structured_log_riverpod/README.md),
   [emb/structured_log_auto_route/](emb/structured_log_auto_route/README.md),
   [emb/structured_log_shelf/](emb/structured_log_shelf/README.md))
   — но не `CHANGELOG.md` (см. «Коммиты и версионирование»).
5. CI ([.github/workflows/ci.yml](.github/workflows/ci.yml)) должен быть зелёным на всех джобах.
