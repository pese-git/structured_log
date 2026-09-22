---
title: "Пакеты"
---

Шесть библиотек, встраиваемых напрямую в собственное Dart- или
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

Страница каждого пакета ниже — это его README дословно: установка,
быстрый старт, полный список возможностей и таблица API.
