# structured_log_shelf

[![CI](https://github.com/pese-git/structured_log/actions/workflows/ci.yml/badge.svg)](https://github.com/pese-git/structured_log/actions/workflows/ci.yml)

*Read in [English](README.md).*

**Записывает каждый запрос к вашему серверу на
[`shelf`](https://pub.dev/packages/shelf) в лог
[`structured_log`](https://pub.dev/packages/structured_log) и даёт
обработчику логгер, по записям которого видно, к какому запросу они
относятся.**

## Зачем это нужно

Пользователь сообщает, что в 10:42 у него не сохранились данные. В журнале
сервера за 10:42 есть ответ 500, а рядом — сообщение обработчика «квота
исчерпана». Но относится ли оно к этому запросу или к другому, пришедшему в ту
же секунду? Пока записи обработчика ничем не связаны с запросом, который их
вызвал, ответить на этот вопрос нельзя.

`structuredLogRequests()` — обычный `Middleware` для shelf. Поставьте его
первым в `Pipeline`, и каждый запрос будет попадать в лог одной записью:
метод, путь, статус ответа и время обработки. Уровень записи зависит от
статуса. Каждому запросу присваивается идентификатор, а обработчик получает
логгер, уже привязанный к нему, — `request.logger`. Поэтому всё, что пишет
обработчик, содержит тот же `request_id`, что и запись о самом запросе.
Идентификатор возвращается клиенту в заголовке `X-Request-Id` — его можно
указать в обращении в поддержку.

## Возможности

### Что попадает в лог

- **Одна запись на запрос** — `http_request_handled` со `status_code` и
  `duration_ms` или, если обработчик выбросил исключение,
  `http_request_failed` с текстом ошибки и стеком вызовов.
- **Связь с запросом внутри обработчика** — записи через `request.logger`
  содержат `request_id` запроса, а `request.requestId` возвращает сам
  идентификатор.
- **Идентификатор возвращается клиенту** в `X-Request-Id`, чтобы
  пользователь или журнал клиента могли сослаться на конкретный запрос.
- **Уровень по статусу ответа** — 2xx и 3xx пишутся на уровне `info`, 4xx —
  `warning`, 5xx и исключения обработчика — `error`. Каждый уровень можно
  изменить или отключить.
- **Отдельная категория** — `category: 'http'`, та же, что у HTTP-адаптеров на
  клиенте, поэтому фильтр `status_code >= 500` одинаково находит записи и
  сервера, и клиента.

### Что в лог не попадает

- **Тела запросов и ответов — никогда.** Такой настройки нет вовсе: сервер
  получает пароли и чужие персональные данные.
- **Заголовки — только по явному разрешению.** При `logHeaders: true` значения
  `Authorization`, cookie и заголовков с API-ключами заменяются на
  `REDACTED`.
- **Токены в строке запроса** маскируются всегда, откуда бы ни пришёл запрос.
- **Идентификаторы, присланные клиентом.** Входящему `X-Request-Id` пакет не
  доверяет, пока вы этого явно не разрешите, и даже тогда принимает его, только
  если значение похоже на идентификатор.

### Что не мешает работе

- **Подключается одной строкой** — `.addMiddleware(structuredLogRequests())`.
- **Не влияет на ответ.** Если фильтр или синк выбросит исключение,
  пропадёт только запись, а запрос будет обработан как обычно. Исключение
  обработчика пробрасывается дальше без изменений, с исходным стеком.
  Захваченный обработчиком сокет остаётся в его распоряжении.
- **Учитывает смену конфигурации** — если логгер не передан явно, middleware
  подхватывает конфигурацию, заданную позже через
  `StructlogConfiguration.configure`.

## Место в проекте

`structured_log_shelf` — одна из интеграций для
[`structured_log`](https://pub.dev/packages/structured_log) и единственная,
которая работает на стороне сервера. Пакет зависит только от ядра и `shelf` и
пишет в уже настроенные вами синки: в консоль, в файл через
`package:structured_log/io.dart` или в self-hosted `structured_log_server`
через [`structured_log_remote_sync`](https://pub.dev/packages/structured_log_remote_sync).
Имена записей и полей совпадают с теми, что у
[`structured_log_dio`](https://pub.dev/packages/structured_log_dio) и
[`structured_log_http_client`](https://pub.dev/packages/structured_log_http_client),
поэтому запрос можно проследить от клиента, который его отправил, до
обработчика, который на него ответил. Всего в семействе десять адаптеров,
которые записывают в лог то, что библиотеки вашего приложения и так делают;
подробнее о проекте — на
[structured-log.openidealab.com](https://structured-log.openidealab.com/ru/).

## Установка

Опубликован на pub.dev как пре-релиз:

```yaml
dependencies:
  shelf: ^1.4.0
  structured_log: ^0.3.2
  structured_log_shelf: ^0.1.0-dev.1
```

## Быстрый старт

```dart
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_shelf/structured_log_shelf.dart';

Future<void> main() async {
  StructlogConfiguration.configure(
    sinks: [LogSink(name: 'console', output: jsonLineOutput)],
  );

  final handler = const Pipeline()
      .addMiddleware(structuredLogRequests())
      .addHandler((request) {
    request.logger.info('items_listed', context: {'count': 1});
    return Response.ok('[{"id":1}]');
  });

  await shelf_io.serve(handler, InternetAddress.loopbackIPv4, 8080);
}
```

Запрос `GET /items?access_token=s3cr3t` даст такие записи:

```text
{"logger":"shelf","count":1,"request_id":"be47bb449d83","event":"items_listed","level":"info",…}
{"logger":"shelf","category":"http","method":"GET","path":"/items","query":"access_token=REDACTED","status_code":200,"duration_ms":10.255,"request_id":"be47bb449d83","event":"http_request_handled","level":"info",…}
```

а в ответе будет заголовок `X-Request-Id: be47bb449d83`. Пример
[example/main.dart](example/main.dart) запускает сервер на loopback-интерфейсе
и сам отправляет ему три запроса: успешный, отклонённый и такой, на котором
обработчик выбрасывает исключение (`dart run example/main.dart`).

**Ставьте middleware первым в `Pipeline`.** Тогда в лог попадёт именно тот
статус, который получил клиент, — в том числе если ответ сформировал другой
middleware, стоящий после него.

**Исключения должен превращать в ответы middleware обработки ошибок, стоящий
после этого.** Если исключение обработчика не перехватил ни один middleware,
ответ 500 формирует сам `shelf_io`, уже за пределами `structuredLogRequests`.
Сбой при этом записан (`http_request_failed`), но заголовка `X-Request-Id` в
таком ответе нет. Если же между этим middleware и обработчиком стоит
middleware обработки ошибок, ответ 500 проходит обратно через
`structuredLogRequests`, получает заголовок и записывается как
`http_request_handled` со `status_code: 500`.

## Какие записи создаются

| Запись                  | Когда                                 | Поля |
|-------------------------|---------------------------------------|------|
| `http_request_handled`  | обработчик вернул ответ               | `method`, `path`, `query` (если есть), `status_code`, `duration_ms`; при включённых заголовках — `request_headers` и `response_headers` |
| `http_request_handled`  | обработчик захватил сокет (`request.hijack`, так работают WebSocket) | `method`, `path`, `query` (если есть), `hijacked: true`, `duration_ms`; статуса нет, потому что ответа не было |
| `http_request_failed`   | обработчик выбросил исключение        | `method`, `path`, `query` (если есть), `duration_ms`, `error`, `error_type`, `stack_trace` |
| `http_request_received` | перед вызовом обработчика — **по умолчанию отключена** (`ShelfLogLevels(received: …)`) | `method`, `path`, `query` (если есть) |

В каждой записи есть `request_id` и `category` (по умолчанию `http`), а если
входящий идентификатор был отклонён — ещё и `request_id_rejected: true`.

- **`path` — путь из исходного запроса** (`request.requestedUri`), поэтому он
  не зависит от того, в каком месте приложения смонтирован middleware.
- **`duration_ms` — дробное число миллисекунд до момента, когда обработчик
  вернул ответ**, то есть без времени отправки тела. Для потока server-sent
  events это время до первого байта. Чтобы видеть долгий запрос, пока он ещё
  не завершён, включите запись `http_request_received`.
- **Записи обработчика идут с `logger: shelf`**, потому что они пишутся через
  логгер middleware, к которому привязан идентификатор. Другое имя можно
  задать, передав свой логгер в параметре `logger:`.

## Идентификаторы запросов

Каждому запросу присваивается идентификатор: по умолчанию это 12 случайных
шестнадцатеричных символов, а при заданном `requestIdGenerator` — то, что он
вернёт (например, UUID). Идентификатор попадает в поле `request_id` всех
записей запроса — и самого middleware, и обработчика — и возвращается клиенту
в заголовке `X-Request-Id`. Имя заголовка задаётся параметром
`responseHeader`, а значение `null` отключает его.

```dart
Response handle(Request request) {
  request.logger.warning('quota_exceeded'); // запись содержит request_id
  return Response(429, body: 'Quota exceeded, request ${request.requestId}');
}
```

**Если перед обработчиком нет middleware, обращение к `request.logger`
выбрасывает `StateError`.** Можно было бы молча вернуть логгер без
идентификатора, но тогда записи обработчика оказались бы ни с чем не
связаны, и никто бы этого не заметил, а пакет создан как раз для того, чтобы
такого не происходило. Поэтому в тестах обработчика, который использует
`request.logger`, middleware нужно ставить перед ним так же, как на сервере:

```dart
final handler = const Pipeline()
    .addMiddleware(structuredLogRequests())
    .addHandler(handle);
final response = await handler(
  Request('GET', Uri.parse('http://localhost/ingest')),
);
```

**Идентификатор, присланный клиентом, по умолчанию игнорируется.** Иначе
клиент мог бы подставить идентификатор чужого запроса или произвольный текст,
и он попал бы в журнал без изменений. Если сервер работает за прокси, который
сам проставляет идентификатор, включите `trustIncomingRequestId`, а если
заголовок называется не `X-Request-Id` — укажите его в
`incomingRequestIdHeader`. Но и в этом случае значение принимается, только
если оно состоит из 1–128 символов набора `A–Z a–z 0–9 . _ : -`. Иначе
middleware создаёт новый идентификатор, добавляет в запись
`request_id_rejected: true`, а само отклонённое значение никуда не пишет.

## Защита секретов

- **Тела запросов и ответов не записываются никогда.** Такой настройки нет:
  сервер обрабатывает пароли, токены и чужие данные, а читать его журнал могут
  люди, которым эти данные не предназначены.
- **Заголовки по умолчанию не записываются.** При `logHeaders: true` значения
  заголовков из `defaultRedactedHeaders` — `authorization`,
  `proxy-authorization`, `cookie`, `set-cookie`, `x-api-key` — заменяются на
  `REDACTED`. Список можно изменить параметром `redactedHeaders`; имена
  сравниваются без учёта регистра. Переданный список заменяет стандартный, а
  не дополняет его, поэтому, чтобы добавить имена, включите в свой список и
  стандартные.
- **Параметры строки запроса** из `defaultRedactedQueryParameters` —
  `access_token`, `refresh_token`, `id_token`, `token`, `api_key`, `apikey`,
  `password`, `client_secret` — маскируются всегда; список меняется
  параметром `redactedQueryParameters`. Оба стандартных списка совпадают с
  теми, что использует `structured_log_dio`.
- **Секрет внутри пути middleware распознать не может.** Он видит путь
  `/reset/3f9a…`, а не шаблон маршрута `/reset/<token>`, и не может отличить
  токен от остальной части пути. Такие маршруты исключайте из журнала с
  помощью `filter`.
- **Текст исключения обработчика записывается.** В поле `error` попадает
  `toString()` исключения, как и везде в `structured_log`. Некоторые
  исключения содержат в тексте данные — например, драйвер базы данных может
  привести значения параметров запроса, на котором произошла ошибка. Такие
  исключения перехватывайте до того, как они дойдут до middleware.

## Настройка

```dart
structuredLogRequests(
  // Какие исходы записываются и на каком уровне; null отключает запись.
  levels: const ShelfLogLevels(
    received: LogLevel.debug,
    success: LogLevel.debug,
  ),
  // Проверки работоспособности в журнал не попадают, но идентификатор у них есть.
  filter: (request) => request.url.path != 'health',
  logHeaders: true,
  redactedHeaders: {...defaultRedactedHeaders, 'x-tenant-secret'},
  requestIdGenerator: () => const Uuid().v4(), // package:uuid
  trustIncomingRequestId: true, // сервер за прокси, который ставит X-Request-Id
);
```

**`filter` определяет только записи самого middleware, но не привязку к
запросу.** Отфильтрованный запрос всё равно получает идентификатор,
`request.logger` и заголовок ответа. Иначе маршрут, исключённый из журнала,
чтобы не засорять его, потерял бы идентификатор и в записях своего
обработчика. Если фильтр выбросит исключение, записи об этом запросе не
появятся (принцип fail-closed), но сам запрос будет обработан.

## Справочник API

| Символ | Описание |
|---|---|
| `structuredLogRequests({logger, loggerName, category, levels, filter, logHeaders, redactedHeaders, redactedQueryParameters, requestIdGenerator, responseHeader, trustIncomingRequestId, incomingRequestIdHeader})` | Сам middleware. Если `logger` не передан, на каждом запросе вызывается `getLogger(loggerName)` (по умолчанию `shelf`), поэтому конфигурация, заданная позже через `StructlogConfiguration.configure`, тоже применяется. При `category: null` категория не добавляется. |
| `ShelfLogLevels({received, success, clientError, serverError, failure})` | Уровень `LogLevel?` для каждого исхода; `null` отключает запись. Для `received` по умолчанию `null`. |
| `request.logger` | `BoundLogger`, привязанный к `request_id` запроса. Без middleware выбрасывает `StateError`. |
| `request.requestId` | Идентификатор запроса. Без middleware выбрасывает `StateError`. |
| `defaultRedactedHeaders`, `defaultRedactedQueryParameters`, `redactedValue` | Стандартные списки маскирования и значение (`REDACTED`), которым заменяется найденное. |
| `defaultRequestIdHeader` | `X-Request-Id` — имя заголовка ответа и входящего заголовка по умолчанию. |

## Связанные пакеты

Остальные пакеты семейства `structured_log`:

**Ядро**

- [`structured_log`](https://pub.dev/packages/structured_log) — структурированное JSON-логирование с привязкой контекста, процессорами и маршрутизацией по синкам

**Просмотрщик логов в приложении**

- [`structured_log_flutter`](https://pub.dev/packages/structured_log_flutter) — headless-ядро просмотрщика: `LogBuffer` и `LogViewerController`
- [`structured_log_material`](https://pub.dev/packages/structured_log_material) — просмотрщик на Material 3
- [`structured_log_fluent`](https://pub.dev/packages/structured_log_fluent) — просмотрщик на Fluent UI (в стиле WinUI)
- [`structured_log_cupertino`](https://pub.dev/packages/structured_log_cupertino) — просмотрщик на Cupertino (в стиле iOS)

**Доставка логов на сервер**

- [`structured_log_remote_sync`](https://pub.dev/packages/structured_log_remote_sync) — синк с батчингом и повторами для self-hosted `structured_log_server`

**Интеграции**

- [`structured_log_bloc`](https://pub.dev/packages/structured_log_bloc) — `BlocObserver` для `bloc`/`flutter_bloc`
- [`structured_log_dio`](https://pub.dev/packages/structured_log_dio) — перехватчик `dio`, логирующий HTTP-вызовы
- [`structured_log_http_client`](https://pub.dev/packages/structured_log_http_client) — обёртка клиента `package:http`, логирующая HTTP-вызовы
- [`structured_log_go_router`](https://pub.dev/packages/structured_log_go_router) — логирует навигацию `go_router`
- [`structured_log_auto_route`](https://pub.dev/packages/structured_log_auto_route) — логирует навигацию `auto_route`
- [`structured_log_cherrypick`](https://pub.dev/packages/structured_log_cherrypick) — наблюдатель DI-контейнера `cherrypick`
- [`structured_log_drift`](https://pub.dev/packages/structured_log_drift) — `QueryInterceptor` для drift, логирующий запросы, сбои и транзакции
- [`structured_log_logging`](https://pub.dev/packages/structured_log_logging) — мост, передающий записи `package:logging` в `structured_log`
- [`structured_log_riverpod`](https://pub.dev/packages/structured_log_riverpod) — `ProviderObserver` для `riverpod`/`flutter_riverpod`

## Лицензия

См. [LICENSE](LICENSE).
