# structured_log_http_client

[![CI](https://github.com/pese-git/structured_log/actions/workflows/ci.yml/badge.svg)](https://github.com/pese-git/structured_log/actions/workflows/ci.yml)

*Читать на [русском](README.ru.md).*

**Every request your [`package:http`](https://pub.dev/packages/http) client
sends, and how it ended, as a [`structured_log`](https://pub.dev/packages/structured_log)
entry — with tokens and passwords kept out of it, and without buffering a
single response.**

## Why

A bug report says "sync failed". Which call was it, what did the server
answer, how long did it take? A request log answers that — but
`package:http` has no interceptors to hang one on, and a naive log also
writes down the user's access token, session cookie and password and sends
them wherever your logs go.

`StructuredLogHttpClient` is a client that wraps another: hand it the
`http.Client` you would have used, and use it in its place. Every call then
becomes two entries — the request and its outcome, tied together by an id,
with the status code and duration, at a level that follows the status.
Headers and bodies stay out until you ask for them, and even then
credentials are masked before anything is written; your code still gets
every response exactly as the server sent it.

## Features

### What you see

- **Request and outcome, paired** — `http_request_id` ties a call's two
  entries together; the outcome carries `status_code` and `duration_ms`.
- **Levels by status** — 2xx/3xx at `debug`, 4xx at `warning`, 5xx and
  failures at `error`, aborts at `debug`; each adjustable or off.
- **Failures and aborts too** — when the inner client throws, or a request
  is aborted through its `abortTrigger`, the outcome is an `http_error`
  with the exception's type and message.
- **Its own category** — every entry carries `category: 'http'`, for a
  `LogSink` to route and the log viewer to filter on.

### What stays out

- **Headers and bodies off by default** — nothing but the method, URL,
  status and timing is written until you turn them on.
- **Credentials masked when they are on** — `Authorization`, cookies and
  API-key headers become `REDACTED`, and so do password- and token-like
  fields in a JSON or form body, at any depth, by the same list
  `structured_log` itself uses.
- **URLs cleaned always** — token-like query parameters and user info
  (`https://user:pass@host`) never reach the log.

### What doesn't get in the way

- **Wraps any client** — `IOClient`, `BrowserClient`, `cupertino_http`,
  `cronet_http`, a `RetryClient`: whatever `http.Client` you already use.
- **Response bodies without buffering** — with response bodies logged, the
  body still reaches your code as it arrives; only its start is kept for
  the log.
- **Never breaks a call** — a describer or filter that throws costs the
  entry, not the request; the inner client's exceptions reach you
  unchanged.
- **Follows reconfiguration** — without an explicit logger it picks up a
  later `StructlogConfiguration.configure`, so a client built at startup
  needs no rebuilding.

## Where it fits

`structured_log_http_client` is one of the integrations around
[`structured_log`](https://pub.dev/packages/structured_log): it depends on
nothing but the core and `http`, and writes through the sinks you have
already configured. Its sibling
[`structured_log_dio`](https://pub.dev/packages/structured_log_dio) writes
the same entries — same names, fields, levels and redaction — for `dio`,
so an app that uses both clients gets one consistent log. No server is
needed: the entries go to the console, a file, or the in-app log viewer
([`structured_log_flutter`](https://pub.dev/packages/structured_log_flutter)
with a Material, Fluent or Cupertino skin), and — if you run the
self-hosted `structured_log_server` — to it through
[`structured_log_remote_sync`](https://pub.dev/packages/structured_log_remote_sync),
where your team can search them by status, URL or request id. More at
[structured-log.openidealab.com](https://structured-log.openidealab.com).

## Installation

Published on pub.dev as a pre-release (`0.1.0-dev.3`):

```yaml
dependencies:
  http: ^1.5.0
  structured_log: ^0.3.0
  structured_log_http_client: ^0.1.0-dev.3
```

**Breaking change in `0.1.0-dev.3`** (for those upgrading from `0.1.0-dev.2`):
with a body turned on, a textual body whose content type is neither JSON
nor a form is now written only by its size, `<N bytes>`, instead of as it
is. `logUnrecognizedBodies: true` brings the old behaviour back. See
[Keeping secrets out of the log](#keeping-secrets-out-of-the-log).

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
| `http_error`    | no response: the inner client threw, or the request was aborted; with `logResponseBody`, also a body that failed or was aborted half-way | the above, `status_code` if the headers had arrived, `error_type` (the exception's type), `error` |

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
- **Bodies, once on, are redacted before they are written.** Fields named
  in `redactedBodyFields` become `REDACTED`, at any depth and regardless of
  case. The default, `defaultRedactedBodyFields`, is `structured_log`'s own
  `defaultSensitiveKeys` — `password`, `token`, `access_token`,
  `client_secret`, `api_key`, `authorization` and their spelling variants —
  so a body and a log entry are redacted by one list. What gets redacted
  depends on the content type:
  - JSON (`application/json`, `*+json`) or a form
    (`application/x-www-form-urlencoded`) — the body is parsed, redacted
    and written back. To be parsed it is read whole, up to 64 KiB; one that
    does not parse, or is longer, is written as `<unparseable body>`, since
    what cannot be parsed cannot be redacted;
  - any other textual type — only the body's size, `<N bytes>`: there is no
    knowing where a secret sits in text of unknown shape.
    `logUnrecognizedBodies: true` writes such bodies as they are.

  The result is then cut to 1000 characters. Your code always receives the
  body unchanged — only the log sees the redacted copy. To redact more than
  the defaults, spread them into your own set — passing a set replaces the
  defaults rather than adding to them:

```dart
StructuredLogHttpClient(
  http.Client(),
  logRequestBody: true,
  logResponseBody: true,
  redactedBodyFields: {...defaultRedactedBodyFields, 'otp', 'pin'},
);
```

`describeBody` receives the body's text already redacted, or a placeholder
for what cannot be shown: `<N bytes>` for a binary content type or text of
an unrecognized one, `<unparseable body>`, `<stream>` for a
`StreamedRequest`, `<multipart: 2 fields, 1 files>` for a
`MultipartRequest`. Returning `null` from it leaves the field out.

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
| `StructuredLogHttpClient(inner, {logger, loggerName, category, levels, logHeaders, logRequestBody, logResponseBody, redactedHeaders, redactedQueryParameters, describeBody, filter, redactedBodyFields, logUnrecognizedBodies})` | The client. `close()` closes `inner`. Without `logger` it calls `getLogger(loggerName)` (`http`) on every entry, so a later `StructlogConfiguration.configure` reaches it too. `category: null` binds no category. |
| `HttpLogLevels({request, success, clientError, serverError, failure, cancel})` | A `LogLevel?` per outcome; `null` turns it off. |
| `HttpBodyDescriber` | `Object? Function(String body)` — turns a body's text, already redacted (or a placeholder), into an entry value; `null` omits the field. |
| `describeHttpBody(body)` | The default describer: the body cut to `defaultHttpBodyMaxLength` (1000) characters. |
| `redactedBodyFields` | Body field names whose values become `REDACTED`, case-insensitively, at any depth. Defaults to `defaultRedactedBodyFields`; a set passed here replaces it. |
| `logUnrecognizedBodies` | Whether a textual body that is neither JSON nor a form is written as it is. `false` by default: it is written as `<N bytes>`. |
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
- [`structured_log_dio`](https://pub.dev/packages/structured_log_dio) — `dio` interceptor that logs HTTP calls
- [`structured_log_go_router`](https://pub.dev/packages/structured_log_go_router) — logs `go_router` navigation
- [`structured_log_cherrypick`](https://pub.dev/packages/structured_log_cherrypick) — observer for the `cherrypick` DI container

## License

See [LICENSE](LICENSE).
