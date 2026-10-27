---
title: "Пакеты"
---

Шестнадцать библиотек, встраиваемых напрямую в собственное Dart- или
Flutter-приложение — а `structured_log_shelf` в Dart-сервер, —
устанавливаете, импортируете и пользуетесь. (Про
self-hosted сервер и его admin-клиент — см. [руководства](/ru/guides/).)

| Пакет | Что это |
|---|---|
| [structured_log](/ru/packages/structured_log/) | Базовая библиотека — структурированное JSON-логирование с привязкой контекста, процессорами и маршрутизацией по нескольким выходам. Начните с неё независимо от платформы. |
| [structured_log_flutter](/ru/packages/structured_log_flutter/) | Headless-ядро просмотра логов для Flutter: ограниченный `LogBuffer`-sink и фильтрующий `LogViewerController`. Постройте свой UI поверх него или используйте один из трёх готовых скинов ниже. |
| [structured_log_material](/ru/packages/structured_log_material/) | Готовый к использованию просмотрщик логов на Material 3, построенный поверх `structured_log_flutter`. |
| [structured_log_fluent](/ru/packages/structured_log_fluent/) | Готовый к использованию просмотрщик логов на Fluent UI (в стиле WinUI), построенный поверх `structured_log_flutter`. |
| [structured_log_cupertino](/ru/packages/structured_log_cupertino/) | Готовый к использованию просмотрщик логов на Cupertino (в стиле iOS), построенный поверх `structured_log_flutter`. |
| [structured_log_remote_sync](/ru/packages/structured_log_remote_sync/) | Sink `RemoteSyncLogOutput`, отправляющий записи на экземпляр `structured_log_server` по HTTP — батчинг, retry с backoff, ограниченный буфер. Полный разбор приёма логов — в [Руководстве разработчика](/ru/guides/developer-guide/). |
| [structured_log_bloc](/ru/packages/structured_log_bloc/) | `BlocObserver`, который пишет жизненный цикл, события, смену состояния и ошибки каждого блока и кубита записями `structured_log`. Работает с `flutter_bloc` как есть. |
| [structured_log_riverpod](/ru/packages/structured_log_riverpod/) | `ProviderObserver`, который пишет создание, обновления, сбои и удаление каждого провайдера Riverpod записями `structured_log`. Работает с `flutter_riverpod` как есть; только Riverpod 3. |
| [structured_log_dio](/ru/packages/structured_log_dio/) | Перехватчик `dio`, который пишет каждый запрос и его итог с уровнем по статусу ответа и маскирует заголовки авторизации, cookie и query-параметры с токенами. |
| [structured_log_http_client](/ru/packages/structured_log_http_client/) | То же для `package:http`: клиент-обёртка над любым `http.Client`, который пишет каждый проходящий через него вызов. |
| [structured_log_go_router](/ru/packages/structured_log_go_router/) | Пишет каждую навигацию `go_router` — расположение, шаблон маршрута, предыдущее расположение — а также перенаправления и ошибки маршрутизации, маскируя query-параметры с токенами. |
| [structured_log_auto_route](/ru/packages/structured_log_auto_route/) | Пишет каждый экран `auto_route`, который открыли, закрыли или выбрали, — имя, шаблон, расположение, — с замаскированными токенами. |
| [structured_log_cherrypick](/ru/packages/structured_log_cherrypick/) | `CherryPickObserver`, который пишет, что делает DI-контейнер `cherrypick`, — скоупы, модули, циклы, ошибки разрешения — и никогда не печатает экземпляр. |
| [structured_log_drift](/ru/packages/structured_log_drift/) | `QueryInterceptor` для drift, который пишет каждый запрос — SQL, длительность, строки, — а также пакеты, сбои и завершение транзакций, выделяет медленные запросы и по умолчанию не пишет значения аргументов. |
| [structured_log_logging](/ru/packages/structured_log_logging/) | Мост, который пишет каждую запись `package:logging` записью `structured_log` — сообщение, логгер, уровень по значению, ошибку и стек, — так что логи библиотек, пишущих через `package:logging`, попадают в те же выводы, что и ваши. |
| [structured_log_shelf](/ru/packages/structured_log_shelf/) | Middleware `shelf` для Dart-сервера: одна запись на запрос — метод, путь, статус, длительность — и логгер для каждого обработчика, привязанный к `request_id` запроса, который возвращается в `X-Request-Id`. Тела не пишутся никогда. |

Ищете `structured_log_http`? Он переименован в `structured_log_remote_sync`
(`HttpLogOutput` → `RemoteSyncLogOutput`) и больше не развивается;
[его страница](/ru/packages/structured_log_http/) объясняет переход.

Страница каждого пакета ниже — это его README дословно: установка,
быстрый старт, полный список возможностей и таблица API.
