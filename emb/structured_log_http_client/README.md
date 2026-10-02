# structured_log_http_client

[![CI](https://github.com/pese-git/structured_log/actions/workflows/ci.yml/badge.svg)](https://github.com/pese-git/structured_log/actions/workflows/ci.yml)

*Читать на [русском](README.ru.md).*

Logs every request a [`package:http`](https://pub.dev/packages/http) client
sends and how it ended — response, failure, abort — as
[`structured_log`](https://pub.dev/packages/structured_log) entries.

`package:http` has no interceptors, so `StructuredLogHttpClient` is a
client that wraps another: hand it the `http.Client` you would have used,
and use it in its place. Every call then reports through the sinks you have
already configured — the console, a file, the in-app log viewer
(`structured_log_flutter`), or a `structured_log_server` via
`structured_log_remote_sync`.

## Features

- **Wraps any client** — `IOClient`, `BrowserClient`, `cupertino_http`,
  `cronet_http`, a `RetryClient`: whatever `http.Client` you already use
- **Request and outcome, paired** — `http_request_id` ties a call's two
  entries together; the outcome carries `status_code` and `duration_ms`
- **Levels by status** — 2xx/3xx at `debug`, 4xx at `warning`, 5xx and
  failures at `error`, aborts at `debug`; each adjustable or off
- **Secrets stay out by default** — headers and bodies are not logged
  unless asked for; `Authorization`, cookies and API-key headers are
  redacted even then; token-like query parameters and URL user info are
  always redacted
- **Response bodies without buffering** — the body reaches your code as it
  arrives; only its start is kept for the log
- **Never breaks a call** — a describer or filter that throws costs the
  entry, not the request; the inner client's exceptions reach you
  unchanged

## Installation

Not yet published to pub.dev (`0.1.0-dev.0`) — depend on it as a path or
git dependency for now:

```yaml
dependencies:
  http: ^1.5.0
  structured_log: ^0.2.1
  structured_log_http_client:
    path: ../structured_log_http_client # within this monorepo
```

## Quick Start

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
  client.close(); // closes the wrapped client too
}
```

```text
DEBUG: http_request  {"category":"http","http_request_id":1,"method":"GET","url":"https://api.example.com/items?access_token=REDACTED"}
DEBUG: http_response {"category":"http","http_request_id":1,"method":"GET","url":"https://api.example.com/items?access_token=REDACTED","status_code":200,"duration_ms":46}
```

[example/main.dart](example/main.dart) runs offline against a server it
starts itself (`dart run example/main.dart`).

## What gets logged

| Entry           | When                                  | Fields |
|-----------------|---------------------------------------|--------|
| `http_request`  | the request is about to be sent       | `http_request_id`, `method`, `url`; `request_headers`, `request_body` if enabled |
| `http_response` | a response arrived — **any status**   | the above, `status_code`, `duration_ms`; `response_headers`, `response_body` if enabled |
| `http_error`    | no response: the inner client threw, the body failed half-way, or the request was aborted | the above, `status_code` if the headers had arrived, `error_type` (the exception's type), `error` |

`package:http` does not throw on a status code, so a 404 is an
`http_response` at `warning`, not an error. `http_request_id` counts calls
per client instance, starting at 1.

**When `http_response` is written.** Without `logResponseBody` — as soon as
the headers arrive; `duration_ms` is the time to them. With it, the entry
waits for the body: it is written once your code has read the body to the
end, or stopped reading it, and `duration_ms` covers the body too. A
response nobody reads — or a server-sent event stream left open — is
logged only when its reader cancels.

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
- **Bodies, once on, are logged as they are** (cut to 1000 characters). A
  login form or a token response would land in the log verbatim, so either
  keep them off for such calls with `filter`, or pass a `describeBody` that
  withholds them — returning `null` leaves the field out:

```dart
StructuredLogHttpClient(
  http.Client(),
  logRequestBody: true,
  logResponseBody: true,
  describeBody: (body) =>
      body.contains('"password"') ? null : describeHttpBody(body),
);
```

`describeBody` receives the body's text, or a placeholder for what is not
text: `<42 bytes>` for a binary content type, `<stream>` for a
`StreamedRequest`, `<multipart: 2 fields, 1 files>` for a
`MultipartRequest`.

## Configuration

```dart
StructuredLogHttpClient(
  http.Client(),
  // Which outcomes are logged, and at what level; null turns one off.
  levels: const HttpLogLevels(request: null, clientError: LogLevel.info),
  // Leave health checks out — both of a call's entries.
  filter: (request) => request.url.path != '/health',
  category: 'network',
);
```

With `logResponseBody` on, the response handed back is a new
`StreamedResponse` around the original stream, so a client-specific
subtype is not passed through — `IOStreamedResponse.detachSocket`, for
example. `BaseResponseWithUrl.url` is kept.

## API Reference

| Symbol | Description |
|---|---|
| `StructuredLogHttpClient(inner, {logger, loggerName, category, levels, logHeaders, logRequestBody, logResponseBody, redactedHeaders, redactedQueryParameters, describeBody, filter})` | The client. `close()` closes `inner`. Without `logger` it calls `getLogger(loggerName)` (`http`) on every entry, so a later `StructlogConfiguration.configure` reaches it too. `category: null` binds no category. |
| `HttpLogLevels({request, success, clientError, serverError, failure, cancel})` | A `LogLevel?` per outcome; `null` turns it off. |
| `HttpBodyDescriber` | `Object? Function(String body)` — turns a body's text (or placeholder) into an entry value; `null` omits the field. |
| `describeHttpBody(body)` | The default describer: the body cut to `defaultHttpBodyMaxLength` (1000) characters. |
| `defaultRedactedHeaders`, `defaultRedactedQueryParameters`, `redactedValue` | The default redaction sets and the value (`REDACTED`) that replaces what they match. |

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
- [`structured_log_dio`](https://pub.dev/packages/structured_log_dio) — `dio` interceptor that logs HTTP calls
- [`structured_log_go_router`](https://pub.dev/packages/structured_log_go_router) — logs `go_router` navigation
- [`structured_log_cherrypick`](https://pub.dev/packages/structured_log_cherrypick) — observer for the `cherrypick` DI container

## License

See [LICENSE](LICENSE).
