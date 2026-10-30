# structured_log_shelf

[![CI](https://github.com/pese-git/structured_log/actions/workflows/ci.yml/badge.svg)](https://github.com/pese-git/structured_log/actions/workflows/ci.yml)

*Читать на [русском](README.ru.md).*

**Every request your [`shelf`](https://pub.dev/packages/shelf) server
answers, as a [`structured_log`](https://pub.dev/packages/structured_log)
entry — and a logger for the handler that ties its own entries to that
request.**

## Why

A user says "saving failed at 10:42". The server's log has a 500 at 10:42,
and somewhere near it a "quota exceeded" written by a handler — or by
another request at the same moment. Without something that ties a handler's
entries to the request that caused them, there is no telling which.

`structuredLogRequests()` is an ordinary shelf `Middleware`. Put it first in
a `Pipeline`, and every request becomes one entry with its method, path,
status and duration, at a level that follows the status. Each request gets
an id, and the handler gets a logger already bound to it —
`request.logger` — so everything the handler writes carries the same
`request_id` as the request's own entry. The id goes back to the client in
`X-Request-Id`, for a bug report to quote.

## Features

### What you see

- **One entry per request** — `http_request_handled` with `status_code` and
  `duration_ms`, or `http_request_failed` with the error and its stack when
  the handler threw.
- **Correlation inside the handler** — `request.logger` writes with the
  request's `request_id`; `request.requestId` is the id itself.
- **The id goes back** — in `X-Request-Id`, so a user or a client log can
  name the request.
- **Levels by status** — 2xx/3xx at `info`, 4xx at `warning`, 5xx and a
  throwing handler at `error`; each adjustable or off.
- **Its own category** — `category: 'http'`, the same as the HTTP client
  adapters, so `status_code >= 500` filters server and client entries
  alike.

### What stays out

- **Bodies, always** — there is no setting that writes them: a server
  receives passwords and other people's data.
- **Headers off by default** — and with `logHeaders` on, `Authorization`,
  cookies and API-key headers become `REDACTED`.
- **Tokens in the query, always** — token-like query parameters are
  redacted wherever the request came from.
- **Other people's ids** — an incoming `X-Request-Id` is not trusted unless
  you say so, and even then only if it looks like an id.

### What doesn't get in the way

- **One line to install** — `.addMiddleware(structuredLogRequests())`.
- **Never changes a response** — a filter or sink that throws costs the
  entry, not the request; the handler's own exception is rethrown as it
  was, with its stack; a hijacked socket stays the handler's.
- **Follows reconfiguration** — without an explicit logger it picks up a
  later `StructlogConfiguration.configure`.

## Where it fits

`structured_log_shelf` is one of the integrations around
[`structured_log`](https://pub.dev/packages/structured_log), and the only
one for the server side: it depends on nothing but the core and `shelf`,
and writes through the sinks you have already configured — the console, a
file through `package:structured_log/io.dart`, or a self-hosted
`structured_log_server` through
[`structured_log_remote_sync`](https://pub.dev/packages/structured_log_remote_sync).
Its entries use the same names and fields as those of
[`structured_log_dio`](https://pub.dev/packages/structured_log_dio) and
[`structured_log_http_client`](https://pub.dev/packages/structured_log_http_client),
so a request can be followed from the client that sent it to the handler
that answered. It is one of ten adapters that log what your app's
libraries already do; the whole project is at
[structured-log.openidealab.com](https://structured-log.openidealab.com).

## Installation

Published on pub.dev as a pre-release:

```yaml
dependencies:
  shelf: ^1.4.0
  structured_log: ^0.3.2
  structured_log_shelf: ^0.1.0-dev.1
```

## Quick Start

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

`GET /items?access_token=s3cr3t` writes:

```text
{"logger":"shelf","count":1,"request_id":"be47bb449d83","event":"items_listed","level":"info",…}
{"logger":"shelf","category":"http","method":"GET","path":"/items","query":"access_token=REDACTED","status_code":200,"duration_ms":10.255,"request_id":"be47bb449d83","event":"http_request_handled","level":"info",…}
```

and the response carries `X-Request-Id: be47bb449d83`.
[example/main.dart](example/main.dart) serves on loopback and calls itself:
a success, a refusal and a handler that throws (`dart run example/main.dart`).

**Put it first in the `Pipeline`.** The status it records is then the one
the client received, including responses made by middleware inside it.

**Let an error middleware inside it turn exceptions into responses.** A
handler that throws past every middleware is answered by `shelf_io` itself
with a 500, outside this middleware — the failure is logged as
`http_request_failed`, but that 500 carries no `X-Request-Id`. With an error
middleware between this one and the handler, the 500 passes back through
it, gets the header, and is logged as `http_request_handled` with
`status_code: 500`.

## What gets logged

| Entry                   | When                                  | Fields |
|-------------------------|---------------------------------------|--------|
| `http_request_handled`  | the handler returned a response       | `method`, `path`, `query` if any, `status_code`, `duration_ms`; `request_headers`, `response_headers` if enabled |
| `http_request_handled`  | the handler took the socket (`request.hijack`, as WebSockets do) | `method`, `path`, `query` if any, `hijacked: true`, `duration_ms` — no status: there was no response |
| `http_request_failed`   | the handler threw                     | `method`, `path`, `query` if any, `duration_ms`, `error`, `error_type`, `stack_trace` |
| `http_request_received` | before the handler runs — **off by default** (`ShelfLogLevels(received: …)`) | `method`, `path`, `query` if any |

Every entry carries `request_id` and `category` (`http` by default), and
`request_id_rejected: true` when an incoming id was turned down.

- **`path` is the requested path**, from `request.requestedUri`, so it is
  the same wherever the middleware is mounted.
- **`duration_ms` is fractional, and ends when the handler returns its
  response** — before the body is sent. For a server-sent event stream that
  is the time to the first byte; turn on `http_request_received` to see a
  long request while it is still open.
- **The handler's entries are written as `logger: shelf`** — the logger they
  go through is this middleware's, with the id bound to it. Pass `logger:`
  to name it otherwise.

## Request ids

Each request gets an id: 12 random hex characters by default, or what
`requestIdGenerator` returns (a UUID, say). It is bound as `request_id` to
every entry of the request — the middleware's and the handler's — and
returned in `X-Request-Id` (`responseHeader`; `null` leaves the header off).

```dart
Response handle(Request request) {
  request.logger.warning('quota_exceeded'); // carries request_id
  return Response(429, body: 'Quota exceeded, request ${request.requestId}');
}
```

**`request.logger` throws a `StateError` when the middleware is not in
front of the handler.** It could quietly return a logger without the id —
and then the handler's entries would be uncorrelated without anyone
noticing, which is the problem this package exists to solve. A test of a
handler that uses it puts the middleware in front, the same way the server
does:

```dart
final handler = const Pipeline()
    .addMiddleware(structuredLogRequests())
    .addHandler(handle);
final response = await handler(
  Request('GET', Uri.parse('http://localhost/ingest')),
);
```

**An incoming id is ignored unless you trust it.** A client could send the
id of someone else's request, or text that is not an id at all, and it
would land in your log as is. Behind a proxy that sets the id, turn on
`trustIncomingRequestId` (and `incomingRequestIdHeader` if it is not
`X-Request-Id`). Even then the value is used only if it is 1–128
characters of `A–Z a–z 0–9 . _ : -`; anything else is replaced with a fresh
id, the entry gets `request_id_rejected: true`, and the value itself is
written nowhere.

## Keeping secrets out of the log

- **Bodies are never written.** There is no setting for it: a server reads
  passwords, tokens and other people's data, and the people who read its
  log are not necessarily those the data was meant for.
- **Headers are off by default.** With `logHeaders: true`, the values of
  `defaultRedactedHeaders` — `authorization`, `proxy-authorization`,
  `cookie`, `set-cookie`, `x-api-key` — become `REDACTED`. Pass
  `redactedHeaders` to change the set; names are compared
  case-insensitively, and a set passed here replaces the defaults, so
  spread them in to add to them.
- **Query parameters** named in `defaultRedactedQueryParameters` —
  `access_token`, `refresh_token`, `id_token`, `token`, `api_key`, `apikey`,
  `password`, `client_secret` — are always redacted; pass
  `redactedQueryParameters` to change the set. Both default sets are the
  same as `structured_log_dio`'s.
- **A secret in a path segment is not recognised.** The middleware sees
  `/reset/3f9a…`, not the route `/reset/<token>`, so it cannot tell the
  token from the path. Keep such routes out with `filter`.
- **The error text of a throwing handler is written** — `error` is the
  exception's `toString()`, as it is everywhere in `structured_log`. Some
  exceptions quote data (a database driver may quote the failed statement's
  values); catch those before they reach the middleware.

## Configuration

```dart
structuredLogRequests(
  // Which outcomes are logged, and at what level; null turns one off.
  levels: const ShelfLogLevels(
    received: LogLevel.debug,
    success: LogLevel.debug,
  ),
  // Leave health checks out of the log. They still get an id.
  filter: (request) => request.url.path != 'health',
  logHeaders: true,
  redactedHeaders: {...defaultRedactedHeaders, 'x-tenant-secret'},
  requestIdGenerator: () => const Uuid().v4(), // package:uuid
  trustIncomingRequestId: true, // behind a proxy that sets X-Request-Id
);
```

**`filter` decides the middleware's entries, not the correlation.** A
request it rejects still gets its id, `request.logger` and the response
header — otherwise a route kept out of the log for quiet would also lose
the id on what its handler writes. A filter that throws costs the request
its entries (fail-closed), never its response.

## API Reference

| Symbol | Description |
|---|---|
| `structuredLogRequests({logger, loggerName, category, levels, filter, logHeaders, redactedHeaders, redactedQueryParameters, requestIdGenerator, responseHeader, trustIncomingRequestId, incomingRequestIdHeader})` | The middleware. Without `logger` it calls `getLogger(loggerName)` (`shelf`) on every request, so a later `StructlogConfiguration.configure` reaches it too. `category: null` binds no category. |
| `ShelfLogLevels({received, success, clientError, serverError, failure})` | A `LogLevel?` per outcome; `null` turns it off. `received` is `null` by default. |
| `request.logger` | A `BoundLogger` bound to the request's `request_id`. Throws a `StateError` without the middleware. |
| `request.requestId` | The request's id. Throws a `StateError` without the middleware. |
| `defaultRedactedHeaders`, `defaultRedactedQueryParameters`, `redactedValue` | The default redaction sets and the value (`REDACTED`) that replaces what they match. |
| `defaultRequestIdHeader` | `X-Request-Id`: the default response header and incoming header. |

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
- [`structured_log_http_client`](https://pub.dev/packages/structured_log_http_client) — `package:http` client wrapper that logs HTTP calls
- [`structured_log_go_router`](https://pub.dev/packages/structured_log_go_router) — logs `go_router` navigation
- [`structured_log_auto_route`](https://pub.dev/packages/structured_log_auto_route) — logs `auto_route` navigation
- [`structured_log_cherrypick`](https://pub.dev/packages/structured_log_cherrypick) — observer for the `cherrypick` DI container
- [`structured_log_drift`](https://pub.dev/packages/structured_log_drift) — drift `QueryInterceptor` that logs queries, failures and transactions
- [`structured_log_logging`](https://pub.dev/packages/structured_log_logging) — bridge that routes `package:logging` records into `structured_log`
- [`structured_log_riverpod`](https://pub.dev/packages/structured_log_riverpod) — `ProviderObserver` for `riverpod`/`flutter_riverpod`

## License

See [LICENSE](LICENSE).
