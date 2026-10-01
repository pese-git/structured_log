# structured_log_dio

[![CI](https://github.com/pese-git/structured_log/actions/workflows/ci.yml/badge.svg)](https://github.com/pese-git/structured_log/actions/workflows/ci.yml)

*Читать на [русском](README.ru.md).*

Logs every request a [`dio`](https://pub.dev/packages/dio) client sends and
how it ended — response, error, timeout, cancellation — as
[`structured_log`](https://pub.dev/packages/structured_log) entries.

`StructuredLogDioInterceptor` is an ordinary dio `Interceptor`: add it to
`dio.interceptors`, and every call reports through the sinks you have
already configured — the console, a file, the in-app log viewer
(`structured_log_flutter`), or a `structured_log_server` via
`structured_log_http`.

## Features

- **One line to install** — `dio.interceptors.add(StructuredLogDioInterceptor())`
- **Request and outcome, paired** — `http_request_id` ties a call's two
  entries together; the outcome carries `status_code` and `duration_ms`
- **Levels by status** — 2xx/3xx at `debug`, 4xx at `warning`, 5xx and
  failures without a response at `error`, cancellations at `debug`; each
  adjustable or off
- **Secrets stay out by default** — headers and bodies are not logged
  unless asked for; `Authorization`, cookies and API-key headers are
  redacted even then; token-like query parameters and URL user info are
  always redacted
- **Its own category** — every entry carries `category: 'http'`, for a
  `LogSink` to route and the log viewer to filter on
- **Never breaks a call** — a describer or filter that throws costs the
  entry, not the request

## Installation

Not yet published to pub.dev (`0.1.0-dev.0`) — depend on it as a path or
git dependency for now:

```yaml
dependencies:
  dio: ^5.4.0
  structured_log: ^0.2.1
  structured_log_dio:
    path: ../structured_log_dio # within this monorepo
```

## Quick Start

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

[example/main.dart](example/main.dart) runs offline against a server it
starts itself (`dart run example/main.dart`).

**Add the interceptor last.** Interceptors run in order, so the last one
logs the request that actually leaves — with the headers the others
added — and sees each response before any of them can turn it into
something else.

## What gets logged

| Entry           | When                                        | Fields |
|-----------------|---------------------------------------------|--------|
| `http_request`  | the request is about to be sent             | `http_request_id`, `method`, `url`; `request_headers`, `request_body` if enabled |
| `http_response` | a response arrived and `validateStatus` accepted it | the above, `status_code`, `duration_ms`; `response_headers`, `response_body` if enabled |
| `http_error`    | anything else: a rejected status, a timeout, a refused connection, a cancellation | the above, `status_code` if there was a response, `error_type` (the `DioExceptionType`), `error` |

The level of an outcome follows its status code wherever it arrives from,
so a 404 is a `warning` whether `validateStatus` accepted it or not. `error`
is left out for `badResponse`: dio's message for it only restates the
status code.

`http_request_id` counts calls per interceptor instance, starting at 1.

## Keeping secrets out of the log

- **Headers and bodies are off by default.** `logHeaders`,
  `logRequestBody` and `logResponseBody` turn them on.
- **With headers on,** the values of `defaultRedactedHeaders` —
  `authorization`, `proxy-authorization`, `cookie`, `set-cookie`,
  `x-api-key` — become `REDACTED`. Pass `redactedHeaders` to change the
  set (lower-case names; compared case-insensitively).
- **Query parameters** named in `defaultRedactedQueryParameters` —
  `access_token`, `refresh_token`, `id_token`, `token`, `api_key`, `apikey`,
  `password`, `client_secret` — are always redacted; pass
  `redactedQueryParameters` to change the set. User info in the URL
  (`https://user:pass@host`) is always dropped.
- **Bodies, once on, are logged as they are** (JSON-encoded, cut to 1000
  characters). A login form or a token response would land in the log
  verbatim, so either keep them off for such calls with `filter`, or pass a
  `describeBody` that withholds them — returning `null` leaves the field
  out:

```dart
StructuredLogDioInterceptor(
  logRequestBody: true,
  logResponseBody: true,
  describeBody: (body) =>
      body is Map && body.containsKey('password') ? null : describeHttpBody(body),
);
```

## Configuration

```dart
StructuredLogDioInterceptor(
  // Which outcomes are logged, and at what level; null turns one off.
  levels: const HttpLogLevels(request: null, clientError: LogLevel.info),
  // Leave health checks out — both of a call's entries.
  filter: (options) => options.path != '/health',
  category: 'network',
);
```

Raw bytes and streams are summarised rather than dumped
(`<42 bytes>`, `<stream>`, `<FormData: 2 fields, 0 files>`).

## API Reference

| Symbol | Description |
|---|---|
| `StructuredLogDioInterceptor({logger, loggerName, category, levels, logHeaders, logRequestBody, logResponseBody, redactedHeaders, redactedQueryParameters, describeBody, filter})` | The interceptor. Without `logger` it calls `getLogger(loggerName)` (`dio`) on every entry, so a later `StructlogConfiguration.configure` reaches it too. `category: null` binds no category. |
| `HttpLogLevels({request, success, clientError, serverError, failure, cancel})` | A `LogLevel?` per outcome; `null` turns it off. |
| `HttpBodyDescriber` | `Object? Function(Object? body)` — turns a body into an entry value; `null` omits the field. |
| `describeHttpBody(body)` | The default describer: strings as they are, maps and lists JSON-encoded, bytes/streams/`FormData` summarised, cut to `defaultHttpBodyMaxLength` (1000) characters. |
| `defaultRedactedHeaders`, `defaultRedactedQueryParameters`, `redactedValue` | The default redaction sets and the value (`REDACTED`) that replaces what they match. |

## License

See [LICENSE](LICENSE).
