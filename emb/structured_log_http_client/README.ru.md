# structured_log_http_client

[![CI](https://github.com/pese-git/structured_log/actions/workflows/ci.yml/badge.svg)](https://github.com/pese-git/structured_log/actions/workflows/ci.yml)

*Read in [English](README.md).*

Пишет в лог каждый запрос клиента [`package:http`](https://pub.dev/packages/http)
и то, чем он закончился, — ответ, сбой, прерывание — записями
[`structured_log`](https://pub.dev/packages/structured_log).

Перехватчиков у `package:http` нет, поэтому `StructuredLogHttpClient` — это
клиент-обёртка: передайте ему `http.Client`, которым пользовались бы, и
используйте обёртку вместо него. Каждый вызов тогда пишет в уже настроенные
выводы — консоль, файл, встроенный просмотрщик логов
(`structured_log_flutter`) или `structured_log_server` через
`structured_log_remote_sync`.

## Возможности

- **Оборачивает любой клиент** — `IOClient`, `BrowserClient`,
  `cupertino_http`, `cronet_http`, `RetryClient`: любой `http.Client`,
  которым вы уже пользуетесь
- **Запрос и итог связаны** — `http_request_id` связывает две записи
  одного вызова; итог несёт `status_code` и `duration_ms`
- **Уровень по статусу** — 2xx/3xx на `debug`, 4xx на `warning`, 5xx и сбои
  на `error`, прерывание на `debug`; каждый настраивается или выключается
- **Секреты по умолчанию не попадают в лог** — заголовки и тела не пишутся,
  пока их не включить; `Authorization`, cookie и заголовки с API-ключами
  маскируются и тогда; query-параметры, похожие на токены, и user info в
  URL маскируются всегда
- **Тело ответа без буферизации** — оно доходит до вашего кода по мере
  поступления; для лога сохраняется только его начало
- **Никогда не ломает вызов** — бросившая функция описания или фильтр стоят
  записи, а не запроса; исключения внутреннего клиента доходят до вас без
  изменений

## Установка

На pub.dev пока не опубликован (`0.1.0-dev.0`) — подключайте как path- или
git-зависимость:

```yaml
dependencies:
  http: ^1.5.0
  structured_log: ^0.2.1
  structured_log_http_client:
    path: ../structured_log_http_client # внутри этого монорепозитория
```

## Быстрый старт

```dart
import 'package:http/http.dart' as http;
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_http_client/structured_log_http_client.dart';

Future<void> main() async {
  StructlogConfiguration.configure(
    sinks: [LogSink(name: 'console', output: coloredConsoleOutput)],
  );

  final client = StructuredLogHttpClient(http.Client());
  await client.get(Uri.parse('https://api.example.com/items?access_token=s3cr3t'));
  client.close(); // закрывает и обёрнутый клиент
}
```

```text
DEBUG: http_request  {"category":"http","http_request_id":1,"method":"GET","url":"https://api.example.com/items?access_token=REDACTED"}
DEBUG: http_response {"category":"http","http_request_id":1,"method":"GET","url":"https://api.example.com/items?access_token=REDACTED","status_code":200,"duration_ms":46}
```

[example/main.dart](example/main.dart) работает без сети — против сервера,
который сам же и поднимает (`dart run example/main.dart`).

## Что пишется в лог

| Запись          | Когда                                  | Поля |
|-----------------|----------------------------------------|------|
| `http_request`  | запрос вот-вот уйдёт                    | `http_request_id`, `method`, `url`; `request_headers`, `request_body`, если включены |
| `http_response` | пришёл ответ — **с любым статусом**    | всё выше, `status_code`, `duration_ms`; `response_headers`, `response_body`, если включены |
| `http_error`    | ответа нет: внутренний клиент бросил исключение, тело оборвалось на полпути или запрос прерван | всё выше, `status_code`, если заголовки успели прийти, `error_type` (тип исключения), `error` |

`package:http` не бросает исключений из-за статуса, поэтому 404 — это
`http_response` на уровне `warning`, а не ошибка. `http_request_id` считает
вызовы в пределах одного экземпляра клиента, начиная с 1.

**Когда пишется `http_response`.** Без `logResponseBody` — сразу, как
пришли заголовки; `duration_ms` — время до них. С ним запись ждёт тело:
она пишется, когда ваш код дочитал тело до конца или перестал его читать,
и `duration_ms` включает тело. Ответ, который никто не читает, — или поток
server-sent events, оставленный открытым, — попадёт в лог только когда
читатель отпишется.

## Как не пустить секреты в лог

- **Заголовки и тела по умолчанию выключены.** Их включают `logHeaders`,
  `logRequestBody` и `logResponseBody`.
- **При включённых заголовках** значения из `defaultRedactedHeaders` —
  `authorization`, `proxy-authorization`, `cookie`, `set-cookie`,
  `x-api-key` — заменяются на `REDACTED`. Набор меняется параметром
  `redactedHeaders` (имена в нижнем регистре; сравнение без учёта регистра).
- **Query-параметры** из `defaultRedactedQueryParameters` — `access_token`,
  `refresh_token`, `id_token`, `token`, `api_key`, `apikey`, `password`,
  `client_secret` — маскируются всегда; набор меняется параметром
  `redactedQueryParameters`. User info в URL (`https://user:pass@host`)
  отбрасывается всегда.
- **Включённые тела пишутся как есть** (с обрезкой до 1000 символов). Форма
  входа или ответ с токеном попадут в лог дословно, поэтому либо держите их
  выключенными для таких вызовов через `filter`, либо передайте
  `describeBody`, который их скрывает, — возврат `null` убирает поле:

```dart
StructuredLogHttpClient(
  http.Client(),
  logRequestBody: true,
  logResponseBody: true,
  describeBody: (body) =>
      body.contains('"password"') ? null : describeHttpBody(body),
);
```

`describeBody` получает текст тела или заглушку для того, что не текст:
`<42 bytes>` для двоичного content type, `<stream>` для `StreamedRequest`,
`<multipart: 2 fields, 1 files>` для `MultipartRequest`.

## Настройка

```dart
StructuredLogHttpClient(
  http.Client(),
  // Какие итоги писать и с каким уровнем; null выключает.
  levels: const HttpLogLevels(request: null, clientError: LogLevel.info),
  // Health-check — мимо лога, обе записи вызова.
  filter: (request) => request.url.path != '/health',
  category: 'network',
);
```

При включённом `logResponseBody` возвращается новый `StreamedResponse`
поверх исходного потока, поэтому подтип конкретного клиента не
сохраняется — например, `IOStreamedResponse.detachSocket`.
`BaseResponseWithUrl.url` сохраняется.

## Справочник API

| Символ | Описание |
|---|---|
| `StructuredLogHttpClient(inner, {logger, loggerName, category, levels, logHeaders, logRequestBody, logResponseBody, redactedHeaders, redactedQueryParameters, describeBody, filter})` | Клиент. `close()` закрывает `inner`. Без `logger` вызывает `getLogger(loggerName)` (`http`) на каждой записи, поэтому до него доходит и более поздний `StructlogConfiguration.configure`. `category: null` не привязывает категорию. |
| `HttpLogLevels({request, success, clientError, serverError, failure, cancel})` | `LogLevel?` на каждый итог; `null` выключает. |
| `HttpBodyDescriber` | `Object? Function(String body)` — превращает текст тела (или заглушку) в значение записи; `null` убирает поле. |
| `describeHttpBody(body)` | Описание по умолчанию: тело с обрезкой до `defaultHttpBodyMaxLength` (1000) символов. |
| `defaultRedactedHeaders`, `defaultRedactedQueryParameters`, `redactedValue` | Наборы маскирования по умолчанию и значение (`REDACTED`), которым заменяется найденное. |

## Лицензия

См. [LICENSE](LICENSE).
