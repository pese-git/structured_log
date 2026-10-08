# structured_log_dio

[![CI](https://github.com/pese-git/structured_log/actions/workflows/ci.yml/badge.svg)](https://github.com/pese-git/structured_log/actions/workflows/ci.yml)

*Читать на [русском](README.ru.md).*

**Every request your [`dio`](https://pub.dev/packages/dio) client sends,
and how it ended, as a [`structured_log`](https://pub.dev/packages/structured_log)
entry — with tokens and passwords kept out of it.**

## Why

A bug report says "loading failed". Which call was it, what did the server
answer, how long did it take? A request log answers that — but a naive one
also writes down the user's access token, session cookie and password, and
sends them wherever your logs go.

`StructuredLogDioInterceptor` is an ordinary dio `Interceptor`. Add it to
`dio.interceptors`, and every call becomes two entries — the request and
its outcome, tied together by an id, with the status code and duration, at
a level that follows the status. Headers and bodies stay out until you ask
for them, and even then credentials are masked before anything is written.

## Features

### What you see

- **Request and outcome, paired** — `http_request_id` ties a call's two
  entries together; the outcome carries `status_code` and `duration_ms`.
- **Every way a call can end** — a response, a rejected status, a timeout,
  a refused connection, a cancellation: each gets an outcome entry, with
  dio's `error_type` when it is not a plain response.
- **Levels by status** — 2xx/3xx at `debug`, 4xx at `warning`, 5xx and
  failures without a response at `error`, cancellations at `debug`; each
  adjustable or off. A 404 is a `warning` whether `validateStatus` let it
  through or not.
- **Its own category** — every entry carries `category: 'http'`, for a
  `LogSink` to route and the log viewer to filter on.

### What stays out

- **Headers and bodies off by default** — nothing but the method, URL,
  status and timing is written until you turn them on.
- **Credentials masked when they are on** — `Authorization`, cookies and
  API-key headers become `REDACTED`, and so do password- and token-like
  fields in a body, at any depth, by the same list `structured_log` itself
  uses.
- **URLs cleaned always** — token-like query parameters and user info
  (`https://user:pass@host`) never reach the log.

### What doesn't get in the way

- **One line to install** — `dio.interceptors.add(StructuredLogDioInterceptor())`.
- **Never breaks a call** — a describer or filter that throws costs the
  entry, not the request; the interceptor always passes the call on.
- **Follows reconfiguration** — without an explicit logger it picks up a
  later `StructlogConfiguration.configure`, so a `Dio` built at startup
  needs no rebuilding.

## Where it fits

`structured_log_dio` is one of the integrations around
[`structured_log`](https://pub.dev/packages/structured_log): it depends on
nothing but the core and `dio`, and writes through the sinks you have
already configured. Its sibling
[`structured_log_http_client`](https://pub.dev/packages/structured_log_http_client)
writes the same entries — same names, fields, levels and redaction — for
`package:http`, so an app that uses both clients gets one consistent log.
No server is needed: the entries go to the console, a file, or the in-app
log viewer ([`structured_log_flutter`](https://pub.dev/packages/structured_log_flutter)
with a Material, Fluent or Cupertino skin), and — if you run the
self-hosted `structured_log_server` — to it through
[`structured_log_remote_sync`](https://pub.dev/packages/structured_log_remote_sync),
where your team can search them by status, URL or request id. More at
[structured-log.openidealab.com](https://structured-log.openidealab.com).

## Installation

Published on pub.dev as a pre-release:

```yaml
dependencies:
  dio: ^5.4.0
  structured_log: ^0.3.0
  structured_log_dio: ^0.1.0-dev.3
```

**Breaking change in `0.1.0-dev.3`** (for those upgrading from `0.1.0-dev.2`):
with a body turned on, a string body whose content type is neither JSON nor
a form is now written only by its size, `<N chars>`, instead of as it is.
`logUnrecognizedBodies: true` brings the old behaviour back. See
[Keeping secrets out of the log](#keeping-secrets-out-of-the-log).

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
- **Bodies, once on, are redacted before they are written.** Fields named
  in `redactedBodyFields` become `REDACTED`, at any depth and regardless of
  case. The default, `defaultRedactedBodyFields`, is `structured_log`'s own
  `defaultSensitiveKeys` — `password`, `token`, `access_token`,
  `client_secret`, `api_key`, `authorization` and their spelling variants —
  so a body and a log entry are redacted by one list. What gets
  redacted depends on the body:
  - a map or a list — redacted as it is;
  - a string whose content type is JSON (`application/json`, `*+json`) or a
    form (`application/x-www-form-urlencoded`) — parsed, redacted and
    written back; one that does not parse is written as
    `<unparseable body>`, since what cannot be parsed cannot be redacted;
  - a string of any other type — only its length, `<N chars>`: there is no
    knowing where a secret sits in text of unknown shape.
    `logUnrecognizedBodies: true` writes such strings as they are.

  The result is then JSON-encoded and cut to 1000 characters. A
  `describeBody` of your own receives the body already redacted; returning
  `null` from it leaves the field out. To redact more than the defaults,
  spread them into your own set — passing a set replaces the defaults
  rather than adding to them:

```dart
StructuredLogDioInterceptor(
  logRequestBody: true,
  logResponseBody: true,
  redactedBodyFields: {...defaultRedactedBodyFields, 'otp', 'pin'},
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
| `StructuredLogDioInterceptor({logger, loggerName, category, levels, logHeaders, logRequestBody, logResponseBody, redactedHeaders, redactedQueryParameters, describeBody, filter, redactedBodyFields, logUnrecognizedBodies})` | The interceptor. Without `logger` it calls `getLogger(loggerName)` (`dio`) on every entry, so a later `StructlogConfiguration.configure` reaches it too. `category: null` binds no category. |
| `HttpLogLevels({request, success, clientError, serverError, failure, cancel})` | A `LogLevel?` per outcome; `null` turns it off. |
| `HttpBodyDescriber` | `Object? Function(Object? body)` — turns a body, already redacted, into an entry value; `null` omits the field. |
| `describeHttpBody(body)` | The default describer: strings as they are, maps and lists JSON-encoded, bytes/streams/`FormData` summarised, cut to `defaultHttpBodyMaxLength` (1000) characters. |
| `redactedBodyFields` | Body field names whose values become `REDACTED`, case-insensitively, at any depth. Defaults to `defaultRedactedBodyFields`; a set passed here replaces it. |
| `logUnrecognizedBodies` | Whether a string body that is neither JSON nor a form is written as it is. `false` by default: it is written as `<N chars>`. |
| `defaultRedactedHeaders`, `defaultRedactedQueryParameters`, `defaultRedactedBodyFields`, `redactedValue` | The default redaction sets and the value (`REDACTED`) that replaces what they match. `defaultRedactedBodyFields` is `structured_log`'s `defaultSensitiveKeys`. |

## Related packages

The rest of the `structured_log` family:

**Core**

- [`structured_log`](https://pub.dev/packages/structured_log) — structured JSON logging with context binding, processors and multi-sink routing

**In-app log viewer**

- [`structured_log_flutter`](https://pub.dev/packages/structured_log_flutter) — headless viewer core: `LogBuffer` and `LogViewerController`
- [`structured_log_material`](https://pub.dev/packages/structured_log_material) — Material 3 log viewer
- [`structured_log_fluent`](https://pub.dev/packages/structured_log_fluent) — Fluent UI (WinUI-style) log viewer
- [`structured_log_cupertino`](https://pub.dev/packages/structured_log_cupertino) — Cupertino (iOS-style) log viewer

**Shipping logs to a server**

- [`structured_log_remote_sync`](https://pub.dev/packages/structured_log_remote_sync) — batching, retrying sink for a self-hosted `structured_log_server`

**Integrations**

- [`structured_log_bloc`](https://pub.dev/packages/structured_log_bloc) — `BlocObserver` for `bloc`/`flutter_bloc`
- [`structured_log_http_client`](https://pub.dev/packages/structured_log_http_client) — `package:http` client wrapper that logs HTTP calls
- [`structured_log_go_router`](https://pub.dev/packages/structured_log_go_router) — logs `go_router` navigation
- [`structured_log_cherrypick`](https://pub.dev/packages/structured_log_cherrypick) — observer for the `cherrypick` DI container
- [`structured_log_drift`](https://pub.dev/packages/structured_log_drift) — drift `QueryInterceptor` that logs queries, failures and transactions

## License

See [LICENSE](LICENSE).
