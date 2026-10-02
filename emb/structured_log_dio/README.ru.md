# structured_log_dio

[![CI](https://github.com/pese-git/structured_log/actions/workflows/ci.yml/badge.svg)](https://github.com/pese-git/structured_log/actions/workflows/ci.yml)

*Read in [English](README.md).*

Пишет в лог каждый запрос клиента [`dio`](https://pub.dev/packages/dio) и
то, чем он закончился, — ответ, ошибку, таймаут, отмену — записями
[`structured_log`](https://pub.dev/packages/structured_log).

`StructuredLogDioInterceptor` — обычный `Interceptor` из `dio`: достаточно
добавить его в `dio.interceptors`, и каждый вызов пишет в уже настроенные
выводы — консоль, файл, встроенный просмотрщик логов
(`structured_log_flutter`) или `structured_log_server` через
`structured_log_remote_sync`.

## Возможности

- **Подключение одной строкой** — `dio.interceptors.add(StructuredLogDioInterceptor())`
- **Запрос и итог связаны** — `http_request_id` связывает две записи одного
  вызова; итог несёт `status_code` и `duration_ms`
- **Уровень по статусу** — 2xx/3xx на `debug`, 4xx на `warning`, 5xx и сбои
  без ответа на `error`, отмена на `debug`; каждый настраивается или
  выключается
- **Секреты по умолчанию не попадают в лог** — заголовки и тела не пишутся,
  пока их не включить; `Authorization`, cookie и заголовки с API-ключами
  маскируются и тогда, как и поля тела с паролями и токенами;
  query-параметры, похожие на токены, и user info в URL маскируются всегда
- **Своя категория** — каждая запись несёт `category: 'http'`, по которой
  `LogSink` может маршрутизировать, а просмотрщик — фильтровать
- **Никогда не ломает вызов** — если функция описания или фильтр бросят
  исключение, пропадёт запись, а не запрос

## Установка

Опубликован на pub.dev как пре-релиз (`0.1.0-dev.2`):

```yaml
dependencies:
  dio: ^5.4.0
  structured_log: ^0.3.0
  structured_log_dio: ^0.1.0-dev.2
```

**Ломающее изменение после `0.1.0-dev.2`:** при включённых телах строковое
тело, тип содержимого которого не JSON и не форма, теперь пишется не целиком,
а только размером — `<N chars>`. Прежнее поведение возвращает
`logUnrecognizedBodies: true`. Подробнее — в разделе
[Как не пустить секреты в лог](#как-не-пустить-секреты-в-лог).

## Быстрый старт

```dart
import 'package:dio/dio.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_dio/structured_log_dio.dart';

Future<void> main() async {
  StructlogConfiguration.configure(
    sinks: [LogSink(name: 'console', output: coloredConsoleOutput)],
  );

  final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'))
    ..interceptors.add(StructuredLogDioInterceptor());

  await dio.get('/items', queryParameters: {'access_token': 's3cr3t'});
}
```

```text
DEBUG: http_request  {"category":"http","http_request_id":1,"method":"GET","url":"https://api.example.com/items?access_token=REDACTED"}
DEBUG: http_response {"category":"http","http_request_id":1,"method":"GET","url":"https://api.example.com/items?access_token=REDACTED","status_code":200,"duration_ms":59}
```

[example/main.dart](example/main.dart) работает без сети — против сервера,
который сам же и поднимает (`dart run example/main.dart`).

**Добавляйте перехватчик последним.** Перехватчики выполняются по порядку:
последний пишет тот запрос, который действительно уходит (с заголовками,
добавленными остальными), и видит каждый ответ раньше, чем кто-то из них
успеет превратить его во что-то другое.

## Что пишется в лог

| Запись          | Когда                                       | Поля |
|-----------------|---------------------------------------------|------|
| `http_request`  | запрос вот-вот уйдёт                         | `http_request_id`, `method`, `url`; `request_headers`, `request_body`, если включены |
| `http_response` | пришёл ответ, и `validateStatus` его принял | всё выше, `status_code`, `duration_ms`; `response_headers`, `response_body`, если включены |
| `http_error`    | всё остальное: отвергнутый статус, таймаут, отказ в соединении, отмена | всё выше, `status_code`, если ответ был, `error_type` (`DioExceptionType`), `error` |

Уровень итога определяется статусом, откуда бы ответ ни пришёл, поэтому 404 —
это `warning` независимо от того, принял его `validateStatus` или нет. Для
`badResponse` поле `error` не пишется: сообщение `dio` для него лишь
пересказывает статус.

`http_request_id` считает вызовы в пределах одного экземпляра перехватчика,
начиная с 1.

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
  списку. Что именно маскируется, зависит от тела:
  - словарь или список — маскируется как есть;
  - строка с типом содержимого JSON (`application/json`, `*+json`) или формы
    (`application/x-www-form-urlencoded`) разбирается, маскируется и
    собирается обратно; если разобрать её не удалось, пишется
    `<unparseable body>` — то, что не разобрано, не замаскировать;
  - строка любого другого типа — только её длина, `<N chars>`: где в тексте
    неизвестной структуры лежит секрет, знать неоткуда. Чтобы такие строки
    писались как есть, передайте `logUnrecognizedBodies: true`.

  Результат затем кодируется в JSON и обрезается до 1000 символов.
  Собственный `describeBody` получает уже замаскированное тело; возврат
  `null` из него убирает поле. Чтобы маскировать больше, чем по умолчанию,
  включите стандартный набор в свой: переданный набор заменяет его, а не
  дополняет:

```dart
StructuredLogDioInterceptor(
  logRequestBody: true,
  logResponseBody: true,
  redactedBodyFields: {...defaultRedactedBodyFields, 'otp', 'pin'},
);
```

## Настройка

```dart
StructuredLogDioInterceptor(
  // Какие итоги писать и с каким уровнем; null выключает.
  levels: const HttpLogLevels(request: null, clientError: LogLevel.info),
  // Health-check — мимо лога, обе записи вызова.
  filter: (options) => options.path != '/health',
  category: 'network',
);
```

Сырые байты и потоки не выводятся целиком, а кратко описываются
(`<42 bytes>`, `<stream>`, `<FormData: 2 fields, 0 files>`).

## Справочник API

| Символ | Описание |
|---|---|
| `StructuredLogDioInterceptor({logger, loggerName, category, levels, logHeaders, logRequestBody, logResponseBody, redactedHeaders, redactedQueryParameters, describeBody, filter, redactedBodyFields, logUnrecognizedBodies})` | Перехватчик. Без `logger` вызывает `getLogger(loggerName)` (`dio`) на каждой записи, поэтому до него доходит и более поздний `StructlogConfiguration.configure`. `category: null` не привязывает категорию. |
| `HttpLogLevels({request, success, clientError, serverError, failure, cancel})` | `LogLevel?` на каждый итог; `null` выключает. |
| `HttpBodyDescriber` | `Object? Function(Object? body)` — превращает уже замаскированное тело в значение записи; `null` убирает поле. |
| `describeHttpBody(body)` | Описание по умолчанию: строки как есть, словари и списки — в JSON, байты/потоки/`FormData` — кратко, обрезка до `defaultHttpBodyMaxLength` (1000) символов. |
| `redactedBodyFields` | Имена полей тела, значения которых заменяются на `REDACTED`, — без учёта регистра, на любой глубине. По умолчанию `defaultRedactedBodyFields`; переданный набор заменяет его. |
| `logUnrecognizedBodies` | Писать ли как есть строковое тело, которое не JSON и не форма. По умолчанию `false` — пишется `<N chars>`. |
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
- [`structured_log_http_client`](https://pub.dev/packages/structured_log_http_client) — обёртка клиента `package:http`, логирующая HTTP-вызовы
- [`structured_log_go_router`](https://pub.dev/packages/structured_log_go_router) — логирует навигацию `go_router`
- [`structured_log_cherrypick`](https://pub.dev/packages/structured_log_cherrypick) — наблюдатель DI-контейнера `cherrypick`

## Лицензия

См. [LICENSE](LICENSE).
