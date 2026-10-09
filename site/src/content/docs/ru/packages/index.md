---
title: "Пакеты"
---

Одиннадцать библиотек, встраиваемых напрямую в собственное Dart- или
Flutter-приложение — устанавливаете, импортируете и пользуетесь. (Про
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
| [structured_log_dio](/ru/packages/structured_log_dio/) | Перехватчик `dio`, который пишет каждый запрос и его итог с уровнем по статусу ответа и маскирует заголовки авторизации, cookie и query-параметры с токенами. |
| [structured_log_http_client](/ru/packages/structured_log_http_client/) | То же для `package:http`: клиент-обёртка над любым `http.Client`, который пишет каждый проходящий через него вызов. |
| [structured_log_go_router](/ru/packages/structured_log_go_router/) | Пишет каждую навигацию `go_router` — расположение, шаблон маршрута, предыдущее расположение — а также перенаправления и ошибки маршрутизации, маскируя query-параметры с токенами. |
| [structured_log_cherrypick](/ru/packages/structured_log_cherrypick/) | `CherryPickObserver`, который пишет, что делает DI-контейнер `cherrypick`, — скоупы, модули, циклы, ошибки разрешения — и никогда не печатает экземпляр. |
| [structured_log_drift](/ru/packages/structured_log_drift/) | `QueryInterceptor` для drift, который пишет каждый запрос — SQL, длительность, строки, — а также пакеты, сбои и завершение транзакций, выделяет медленные запросы и по умолчанию не пишет значения аргументов. |
| [structured_log_logging](/ru/packages/structured_log_logging/) | Мост, который пишет каждую запись `package:logging` записью `structured_log` — сообщение, логгер, уровень по значению, ошибку и стек, — так что логи библиотек, пишущих через `package:logging`, попадают в те же выводы, что и ваши. |

Ищете `structured_log_http`? Он переименован в `structured_log_remote_sync`
(`HttpLogOutput` → `RemoteSyncLogOutput`) и больше не развивается;
[его страница](/ru/packages/structured_log_http/) объясняет переход.

Страница каждого пакета ниже — это его README дословно: установка,
быстрый старт, полный список возможностей и таблица API.
