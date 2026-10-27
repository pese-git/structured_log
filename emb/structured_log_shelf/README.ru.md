# structured_log_shelf

[![CI](https://github.com/pese-git/structured_log/actions/workflows/ci.yml/badge.svg)](https://github.com/pese-git/structured_log/actions/workflows/ci.yml)

*Read in [English](README.md).*

**Каждый запрос, на который отвечает ваш сервер на
[`shelf`](https://pub.dev/packages/shelf), — записью
[`structured_log`](https://pub.dev/packages/structured_log), а обработчику —
логгер, который связывает его собственные записи с этим запросом.**

## Зачем

Пользователь пишет: «в 10:42 не сохранилось». В журнале сервера в 10:42 —
ответ 500, а рядом «квота исчерпана», которую записал обработчик — этого
запроса или другого, пришедшего в ту же секунду. Без того, что связывает
записи обработчика с вызвавшим их запросом, этого не понять.

`structuredLogRequests()` — обычный `Middleware` для shelf. Поставьте его
первым в `Pipeline`, и каждый запрос станет одной записью с методом, путём,
статусом и длительностью, на уровне по статусу. У каждого запроса есть id, а
обработчик получает логгер, уже привязанный к нему, — `request.logger`, — так
что всё, что пишет обработчик, несёт тот же `request_id`, что и запись самого
запроса. Id возвращается клиенту в `X-Request-Id`, чтобы его можно было
назвать в обращении.

## Возможности

### Что видно

- **Одна запись на запрос** — `http_request_handled` со `status_code` и
  `duration_ms` или `http_request_failed` с ошибкой и стеком, если обработчик
  бросил.
- **Корреляция внутри обработчика** — `request.logger` пишет с `request_id`
  запроса; `request.requestId` — сам id.
- **Id уходит обратно** — в `X-Request-Id`, чтобы пользователь или журнал
  клиента могли назвать запрос.
- **Уровни по статусу** — 2xx/3xx на `info`, 4xx на `warning`, 5xx и
  бросивший обработчик на `error`; каждый настраивается или выключается.
- **Своя категория** — `category: 'http'`, та же, что у HTTP-адаптеров
  клиента, так что `status_code >= 500` одинаково фильтрует записи сервера и
  клиента.

### Что в лог не попадает

- **Тела — никогда.** Настройки, которая писала бы их, нет: сервер принимает
  пароли и чужие данные.
- **Заголовки выключены по умолчанию**, а при включённом `logHeaders`
  `Authorization`, cookie и заголовки с API-ключами становятся `REDACTED`.
- **Токены в query — всегда маскируются**, откуда бы ни пришёл запрос.
- **Чужие id** — входящему `X-Request-Id` нет доверия, пока вы его не
  включите, и даже тогда — только если он похож на id.

### Что не мешает

- **Подключается одной строкой** — `.addMiddleware(structuredLogRequests())`.
- **Никогда не меняет ответ** — бросивший фильтр или sink стоит записи, а не
  запроса; исключение обработчика пробрасывается как было, со своим стеком;
  захваченный сокет остаётся у обработчика.
- **Следует переконфигурации** — без явного логгера подхватывает позднее
  `StructlogConfiguration.configure`.

## Место в проекте

`structured_log_shelf` — одна из интеграций вокруг
[`structured_log`](https://pub.dev/packages/structured_log) и единственная
для серверной стороны: зависит только от ядра и `shelf` и пишет через уже
настроенные вами sink'и — в консоль, в файл через
`package:structured_log/io.dart` или на self-hosted `structured_log_server`
через [`structured_log_remote_sync`](https://pub.dev/packages/structured_log_remote_sync).
Имена записей и полей — те же, что у
[`structured_log_dio`](https://pub.dev/packages/structured_log_dio) и
[`structured_log_http_client`](https://pub.dev/packages/structured_log_http_client),
так что запрос можно проследить от клиента, который его отправил, до
обработчика, который ответил. Это один из десяти адаптеров, которые пишут в
лог то, что библиотеки приложения и так делают; проект целиком — на
[structured-log.openidealab.com](https://structured-log.openidealab.com/ru/).

## Установка

Пока не опубликован на pub.dev (`0.1.0-dev.0`), поэтому подключайте его из
git:

```yaml
dependencies:
  shelf: ^1.4.0
  structured_log: ^0.3.2
  structured_log_shelf:
    git:
      url: https://github.com/pese-git/structured_log.git
      path: emb/structured_log_shelf
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

`GET /items?access_token=s3cr3t` пишет:

```text
{"logger":"shelf","count":1,"request_id":"be47bb449d83","event":"items_listed","level":"info",…}
{"logger":"shelf","category":"http","method":"GET","path":"/items","query":"access_token=REDACTED","status_code":200,"duration_ms":10.255,"request_id":"be47bb449d83","event":"http_request_handled","level":"info",…}
```

а ответ несёт `X-Request-Id: be47bb449d83`.
[example/main.dart](example/main.dart) поднимает сервер на loopback и сам к
нему обращается: успех, отказ и бросивший обработчик
(`dart run example/main.dart`).

**Ставьте его первым в `Pipeline`.** Тогда он пишет тот статус, который
получил клиент, включая ответы middleware внутри него.

**Пусть исключения в ответы превращает middleware ошибок внутри него.**
Обработчику, бросившему мимо всех middleware, отвечает 500 сам `shelf_io` —
снаружи этого middleware: сбой записан как `http_request_failed`, но у такого
ответа нет `X-Request-Id`. С middleware ошибок между этим и обработчиком
ответ 500 проходит обратно через него, получает заголовок и пишется как
`http_request_handled` со `status_code: 500`.

## Что пишется

| Запись                  | Когда                                 | Поля |
|-------------------------|---------------------------------------|------|
| `http_request_handled`  | обработчик вернул ответ               | `method`, `path`, `query`, если есть, `status_code`, `duration_ms`; `request_headers`, `response_headers`, если включены |
| `http_request_handled`  | обработчик забрал сокет (`request.hijack`, как WebSocket) | `method`, `path`, `query`, если есть, `hijacked: true`, `duration_ms` — без статуса: ответа не было |
| `http_request_failed`   | обработчик бросил                     | `method`, `path`, `query`, если есть, `duration_ms`, `error`, `error_type`, `stack_trace` |
| `http_request_received` | до вызова обработчика — **выключена по умолчанию** (`ShelfLogLevels(received: …)`) | `method`, `path`, `query`, если есть |

Каждая запись несёт `request_id` и `category` (по умолчанию `http`), а если
входящий id отвергнут — `request_id_rejected: true`.

- **`path` — запрошенный путь** из `request.requestedUri`, поэтому он один и
  тот же, где бы ни стоял middleware.
- **`duration_ms` дробное и заканчивается, когда обработчик вернул ответ**, —
  до отправки тела. Для потока server-sent events это время до первого
  байта; чтобы видеть долгий запрос, пока он открыт, включите
  `http_request_received`.
- **Записи обработчика пишутся с `logger: shelf`** — они идут через логгер
  этого middleware, к которому привязан id. Чтобы назвать его иначе,
  передайте `logger:`.

## Идентификаторы запросов

У каждого запроса есть id: по умолчанию 12 случайных hex-символов или то, что
вернёт `requestIdGenerator` (например, UUID). Он привязан как `request_id` ко
всем записям запроса — и middleware, и обработчика — и возвращается в
`X-Request-Id` (`responseHeader`; `null` выключает заголовок).

```dart
Response handle(Request request) {
  request.logger.warning('quota_exceeded'); // несёт request_id
  return Response(429, body: 'Quota exceeded, request ${request.requestId}');
}
```

**`request.logger` бросает `StateError`, если перед обработчиком нет
middleware.** Он мог бы тихо вернуть логгер без id — и тогда записи
обработчика остались бы без корреляции, а никто бы этого не заметил; ровно
эту проблему пакет и решает. Тест обработчика, который им пользуется, ставит
middleware перед ним — так же, как сервер:

```dart
final handler = const Pipeline()
    .addMiddleware(structuredLogRequests())
    .addHandler(handle);
final response = await handler(
  Request('GET', Uri.parse('http://localhost/ingest')),
);
```

**Входящий id не используется, пока вы ему не доверите.** Клиент мог бы
прислать id чужого запроса или вовсе не id, и это легло бы в журнал как есть.
За прокси, который ставит id сам, включите `trustIncomingRequestId` (и
`incomingRequestIdHeader`, если это не `X-Request-Id`). Даже тогда значение
берётся, только если это 1–128 символов из `A–Z a–z 0–9 . _ : -`; иначе оно
заменяется новым id, запись получает `request_id_rejected: true`, а само
значение не пишется никуда.

## Как секреты не попадают в лог

- **Тела не пишутся никогда.** Настройки для этого нет: сервер читает пароли,
  токены и чужие данные, а читают его журнал не обязательно те, кому эти
  данные адресованы.
- **Заголовки выключены по умолчанию.** При `logHeaders: true` значения
  `defaultRedactedHeaders` — `authorization`, `proxy-authorization`,
  `cookie`, `set-cookie`, `x-api-key` — становятся `REDACTED`. Набор меняется
  через `redactedHeaders`; имена сравниваются без учёта регистра, и
  переданный набор заменяет умолчания, а не дополняет их — чтобы добавить,
  разверните их в свой.
- **Query-параметры** из `defaultRedactedQueryParameters` — `access_token`,
  `refresh_token`, `id_token`, `token`, `api_key`, `apikey`, `password`,
  `client_secret` — маскируются всегда; набор меняется через
  `redactedQueryParameters`. Оба набора по умолчанию — те же, что у
  `structured_log_dio`.
- **Секрет в сегменте пути не распознаётся.** Middleware видит
  `/reset/3f9a…`, а не маршрут `/reset/<token>`, и токен от пути отличить не
  может. Такие маршруты исключайте через `filter`.
- **Текст ошибки бросившего обработчика пишется** — `error` это `toString()`
  исключения, как везде в `structured_log`. Некоторые исключения цитируют
  данные (драйвер базы может процитировать значения упавшего оператора);
  такие перехватывайте до middleware.

## Настройка

```dart
structuredLogRequests(
  // Какие исходы пишутся и на каком уровне; null выключает.
  levels: const ShelfLogLevels(
    received: LogLevel.debug,
    success: LogLevel.debug,
  ),
  // Health check — вне журнала. Id у него всё равно есть.
  filter: (request) => request.url.path != 'health',
  logHeaders: true,
  redactedHeaders: {...defaultRedactedHeaders, 'x-tenant-secret'},
  requestIdGenerator: () => const Uuid().v4(), // package:uuid
  trustIncomingRequestId: true, // за прокси, который ставит X-Request-Id
);
```

**`filter` решает судьбу записей middleware, а не корреляции.** Отвергнутый
им запрос всё равно получает id, `request.logger` и заголовок ответа — иначе
маршрут, убранный из журнала ради тишины, лишился бы id и в том, что пишет
его обработчик. Бросивший фильтр стоит запросу его записей (fail-closed), но
никогда — ответа.

## Справочник API

| Символ | Описание |
|---|---|
| `structuredLogRequests({logger, loggerName, category, levels, filter, logHeaders, redactedHeaders, redactedQueryParameters, requestIdGenerator, responseHeader, trustIncomingRequestId, incomingRequestIdHeader})` | Middleware. Без `logger` зовёт `getLogger(loggerName)` (`shelf`) на каждом запросе, поэтому позднее `StructlogConfiguration.configure` до него тоже доходит. `category: null` категорию не привязывает. |
| `ShelfLogLevels({received, success, clientError, serverError, failure})` | `LogLevel?` на исход; `null` выключает. `received` по умолчанию `null`. |
| `request.logger` | `BoundLogger`, привязанный к `request_id` запроса. Без middleware бросает `StateError`. |
| `request.requestId` | Id запроса. Без middleware бросает `StateError`. |
| `defaultRedactedHeaders`, `defaultRedactedQueryParameters`, `redactedValue` | Наборы маскирования по умолчанию и значение (`REDACTED`), которым заменяется совпавшее. |
| `defaultRequestIdHeader` | `X-Request-Id`: заголовок ответа и входящий заголовок по умолчанию. |

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
