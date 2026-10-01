---
title: "Пакеты"
---

Восемь библиотек, встраиваемых напрямую в собственное Dart- или
Flutter-приложение — устанавливаете, импортируете и пользуетесь. (Про
self-hosted сервер и его admin-клиент — см. [руководства](/ru/guides/).)

| Пакет | Что это |
|---|---|
| [structured_log](/ru/packages/structured_log/) | Базовая библиотека — структурированное JSON-логирование с привязкой контекста, процессорами и маршрутизацией по нескольким выходам. Начните с неё независимо от платформы. |
| [structured_log_flutter](/ru/packages/structured_log_flutter/) | Headless-ядро просмотра логов для Flutter: ограниченный `LogBuffer`-sink и фильтрующий `LogViewerController`. Постройте свой UI поверх него или используйте один из трёх готовых скинов ниже. |
| [structured_log_material](/ru/packages/structured_log_material/) | Готовый к использованию просмотрщик логов на Material 3, построенный поверх `structured_log_flutter`. |
| [structured_log_fluent](/ru/packages/structured_log_fluent/) | Готовый к использованию просмотрщик логов на Fluent UI (в стиле WinUI), построенный поверх `structured_log_flutter`. |
| [structured_log_cupertino](/ru/packages/structured_log_cupertino/) | Готовый к использованию просмотрщик логов на Cupertino (в стиле iOS), построенный поверх `structured_log_flutter`. |
| [structured_log_http](/ru/packages/structured_log_http/) | Sink `HttpLogOutput`, отправляющий записи на экземпляр `structured_log_server` по HTTP — батчинг, retry с backoff, ограниченный буфер. Полный разбор приёма логов — в [Руководстве разработчика](/ru/guides/developer-guide/). |
| [structured_log_bloc](/ru/packages/structured_log_bloc/) | `BlocObserver`, который пишет жизненный цикл, события, смену состояния и ошибки каждого блока и кубита записями `structured_log`. Работает с `flutter_bloc` как есть. |
| [structured_log_dio](/ru/packages/structured_log_dio/) | Перехватчик `dio`, который пишет каждый запрос и его итог с уровнем по статусу ответа и маскирует заголовки авторизации, cookie и query-параметры с токенами. |

Страница каждого пакета ниже — это его README дословно: установка,
быстрый старт, полный список возможностей и таблица API.
