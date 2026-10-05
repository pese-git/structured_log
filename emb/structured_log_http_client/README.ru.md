# structured_log_http_client

[![CI](https://github.com/pese-git/structured_log/actions/workflows/ci.yml/badge.svg)](https://github.com/pese-git/structured_log/actions/workflows/ci.yml)

*Read in [English](README.md).*

**Каждый запрос клиента [`package:http`](https://pub.dev/packages/http) и то,
чем он закончился, записываются в [`structured_log`](https://pub.dev/packages/structured_log),
причём ни токены, ни пароли в лог не попадают, а ответы не буферизуются.**

## Зачем

В баг-репорте написано «не синхронизировалось». Какой это был вызов, что
ответил сервер, сколько всё заняло? Ответ даёт лог запросов, но
перехватчиков, к которым его можно было бы подключить, у `package:http` нет,
а наивная реализация заодно записывает access-токен пользователя, cookie сессии и
пароль и отправляет их туда же, куда уходят логи.

`StructuredLogHttpClient` — клиент-обёртка: передайте ему `http.Client`,
которым пользовались бы, и работайте через обёртку вместо него. Тогда каждый
вызов даст две записи — запрос и его итог. Они связаны общим id, в итоге есть
статус и длительность, а уровень записи зависит от статуса. Заголовки
и тела не пишутся, пока вы их не включите, а когда включите, учётные данные
маскируются ещё до записи; ваш код при этом получает каждый ответ ровно
таким, каким его прислал сервер.

## Возможности

### Что видно в логе

- **Запрос и итог связаны** — `http_request_id` связывает две записи одного
  вызова; в записи итога есть `status_code` и `duration_ms`.
- **Уровень по статусу** — 2xx/3xx на `debug`, 4xx на `warning`, 5xx и сбои
  на `error`, прерывание на `debug`; каждый уровень можно изменить или выключить.
- **Сбои и прерывания тоже** — если внутренний клиент выбросил исключение или
  запрос прерван через `abortTrigger`, итогом становится `http_error` с
  типом и текстом исключения.
- **Своя категория** — у каждой записи `category: 'http'`: по ней `LogSink`
  может направлять записи, а просмотрщик — фильтровать их.

### Что в лог не попадает

- **Заголовки и тела по умолчанию выключены** — пока их не включить,
  пишутся только метод, URL, статус и время.
- **Учётные данные маскируются и после включения** — `Authorization`,
  cookie и заголовки с API-ключами заменяются на `REDACTED`, как и поля
  JSON- или form-тела с паролями и токенами на любой глубине — по тому же
  списку, что у самого `structured_log`.
- **URL очищается всегда** — query-параметры, похожие на токены, и user info
  (`https://user:pass@host`) в лог не попадают.

### Как это встраивается в приложение

- **Оборачивает любой клиент** — `IOClient`, `BrowserClient`,
  `cupertino_http`, `cronet_http`, `RetryClient`: любой `http.Client`,
  которым вы уже пользуетесь.
- **Тело ответа без буферизации** — даже когда тела ответов пишутся в лог,
  тело доходит до вашего кода по мере поступления; для лога сохраняется
  только его начало.
- **Никогда не ломает вызов** — если функция описания или фильтр выбросят
  исключение, пропадёт запись, а не запрос; исключения внутреннего клиента
  доходят до вас без изменений.
- **Следует за перенастройкой** — без явного логгера подхватывает более
  поздний `StructlogConfiguration.configure`, так что клиент, созданный на
  старте, пересоздавать не нужно.

## Место в проекте

`structured_log_http_client` — одна из интеграций вокруг
[`structured_log`](https://pub.dev/packages/structured_log): кроме ядра и
`http`, он ни от чего не зависит и пишет в уже настроенные выводы. Соседний
[`structured_log_dio`](https://pub.dev/packages/structured_log_dio) пишет те
же записи — с теми же именами, полями, уровнями и маскированием — для `dio`,
так что в приложении с обоими клиентами лог получается единым. Сервер не
нужен: записи уходят в консоль, в файл или во встроенный просмотрщик логов
([`structured_log_flutter`](https://pub.dev/packages/structured_log_flutter)
со скином Material, Fluent или Cupertino), а если у вас развёрнут
self-hosted `structured_log_server` — ещё и на него через
[`structured_log_remote_sync`](https://pub.dev/packages/structured_log_remote_sync),
где команда найдёт их по статусу, URL или id запроса. Подробнее — на
[structured-log.openidealab.com](https://structured-log.openidealab.com/ru/).

## Установка

Опубликован на pub.dev как пре-релиз:

```yaml
dependencies:
  http: ^1.5.0
  structured_log: ^0.3.0
  structured_log_http_client: ^0.1.0-dev.3
```

**Ломающее изменение в `0.1.0-dev.3`** (для тех, кто обновляется с
`0.1.0-dev.2`): при включённых телах текстовое тело, тип содержимого
которого не JSON и не форма, теперь пишется не целиком, а только размером —
`<N bytes>`. Прежнее поведение возвращает `logUnrecognizedBodies: true`.
Подробнее — в разделе
[Как не пустить секреты в лог](#как-не-пустить-секреты-в-лог).

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

[example/main.dart](example/main.dart) работает без сети: он сам поднимает
сервер, к которому обращается (`dart run example/main.dart`).

## Что пишется в лог

| Запись          | Когда                                  | Поля |
|-----------------|----------------------------------------|------|
| `http_request`  | запрос вот-вот уйдёт                    | `http_request_id`, `method`, `url`; `request_headers`, `request_body`, если включены |
| `http_response` | пришёл ответ — **с любым статусом**    | всё выше, `status_code`, `duration_ms`; `response_headers`, `response_body`, если включены |
| `http_error`    | ответа нет: внутренний клиент выбросил исключение или запрос прерван; при `logResponseBody` — ещё и тело, которое оборвалось или было прервано на полпути | всё выше, `status_code`, если заголовки успели прийти, `error_type` (тип исключения), `error` |

`package:http` не выбрасывает исключений из-за статуса, поэтому 404 — это
`http_response` на уровне `warning`, а не ошибка. `http_request_id` —
порядковый номер вызова в пределах одного экземпляра клиента, начиная с 1.

**Когда пишется `http_response`.** Без `logResponseBody` — сразу, как
пришли заголовки, и `duration_ms` — это время до них. С ним запись ждёт тело:
она пишется, когда ваш код дочитал тело до конца или перестал его читать,
и `duration_ms` включает тело. Ответ, который никто не читает, — или поток
server-sent events, оставленный открытым, — попадёт в лог, только когда
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
- **Включённое тело маскируется до того, как попасть в лог.** Поля с именами
  из `redactedBodyFields` заменяются на `REDACTED` на любой глубине и без
  учёта регистра. По умолчанию это `defaultRedactedBodyFields` — тот же
  список `defaultSensitiveKeys`, что у самого `structured_log` (`password`,
  `token`, `access_token`, `client_secret`, `api_key`, `authorization` и их
  варианты написания), так что тело и запись лога маскируются по одному
  списку. Что именно маскируется, зависит от типа содержимого:
  - JSON (`application/json`, `*+json`) или форма
    (`application/x-www-form-urlencoded`) — тело разбирается, маскируется и
    собирается обратно. Для разбора оно читается целиком, но не больше
    64 КиБ; тело, которое не удалось разобрать или которое оказалось длиннее, пишется как
    `<unparseable body>` — то, что не разобрано, не замаскировать;
  - любой другой текстовый тип — только размер тела, `<N bytes>`: где в
    тексте неизвестной структуры лежит секрет, знать неоткуда. Чтобы такие
    тела писались как есть, передайте `logUnrecognizedBodies: true`.

  Результат затем обрезается до 1000 символов. Ваш код всегда получает тело
  без изменений — замаскированную копию видит только лог. Чтобы маскировать
  больше, чем по умолчанию, включите стандартный набор в свой: переданный
  набор заменяет его, а не дополняет:

```dart
StructuredLogHttpClient(
  http.Client(),
  logRequestBody: true,
  logResponseBody: true,
  redactedBodyFields: {...defaultRedactedBodyFields, 'otp', 'pin'},
);
```

`describeBody` получает уже замаскированный текст тела или заглушку для
того, что показать нельзя: `<N bytes>` для двоичного или нераспознанного
текстового content type, `<unparseable body>`, `<stream>` для
`StreamedRequest`, `<multipart: 2 fields, 1 files>` для `MultipartRequest`.
Возврат `null` из него убирает поле.

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
поверх исходного потока, поэтому возможности подтипа конкретного клиента
теряются — например, `IOStreamedResponse.detachSocket`.
`BaseResponseWithUrl.url` сохраняется.

## Справочник API

| Символ | Описание |
|---|---|
| `StructuredLogHttpClient(inner, {logger, loggerName, category, levels, logHeaders, logRequestBody, logResponseBody, redactedHeaders, redactedQueryParameters, describeBody, filter, redactedBodyFields, logUnrecognizedBodies})` | Клиент. `close()` закрывает `inner`. Без `logger` вызывает `getLogger(loggerName)` (`http`) на каждой записи, поэтому до него доходит и более поздний `StructlogConfiguration.configure`. `category: null` не привязывает категорию. |
| `HttpLogLevels({request, success, clientError, serverError, failure, cancel})` | `LogLevel?` на каждый итог; `null` выключает. |
| `HttpBodyDescriber` | `Object? Function(String body)` — превращает уже замаскированный текст тела (или заглушку) в значение записи; `null` убирает поле. |
| `describeHttpBody(body)` | Описание по умолчанию: тело с обрезкой до `defaultHttpBodyMaxLength` (1000) символов. |
| `redactedBodyFields` | Имена полей тела, значения которых заменяются на `REDACTED`, — без учёта регистра, на любой глубине. По умолчанию `defaultRedactedBodyFields`; переданный набор заменяет его. |
| `logUnrecognizedBodies` | Писать ли как есть текстовое тело, которое не JSON и не форма. По умолчанию `false` — пишется `<N bytes>`. |
| `defaultRedactedHeaders`, `defaultRedactedQueryParameters`, `defaultRedactedBodyFields`, `redactedValue` | Наборы маскирования по умолчанию и значение (`REDACTED`), которым заменяется найденное. `defaultRedactedBodyFields` — это `defaultSensitiveKeys` из `structured_log`. |

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
- [`structured_log_go_router`](https://pub.dev/packages/structured_log_go_router) — логирует навигацию `go_router`
- [`structured_log_cherrypick`](https://pub.dev/packages/structured_log_cherrypick) — наблюдатель DI-контейнера `cherrypick`
- [`structured_log_drift`](https://pub.dev/packages/structured_log_drift) — `QueryInterceptor` для drift, логирующий запросы, сбои и транзакции
- [`structured_log_logging`](https://pub.dev/packages/structured_log_logging) — мост, передающий записи `package:logging` в `structured_log`

## Лицензия

См. [LICENSE](LICENSE).
