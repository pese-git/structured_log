# Embedding Guide

*Читать на [русском](embedding-guide.ru.md).*

For whoever wants to add structured logging — and, optionally, a live
in-app log viewer — to their own Dart or Flutter application. Nothing
here talks to `structured_log_server` at all: every package below works
standalone, in a project that never runs the server. If you *do* want to
ship logs to a self-hosted `structured_log_server` instance (or query
them back out of one), see the [Developer Guide](developer-guide.md)
instead — that guide picks up exactly where this one's optional last
section points to it.

Several packages, and you only need as many of them as your project does:

1. **Just logging** — [`structured_log`](#1-structured-logging-structured_log)
   alone. Pure Dart, zero runtime dependencies beyond `meta`, works
   anywhere Dart runs.
2. **A live in-app log view, in Flutter** —
   [`structured_log_flutter`](#2-a-headless-viewer-core-structured_log_flutter)
   (the headless list/filter core) plus one ready-made skin:
   [`structured_log_material`](#3-a-ready-made-skin),
   [`structured_log_fluent`](#3-a-ready-made-skin), or
   [`structured_log_cupertino`](#3-a-ready-made-skin) — pick the one
   matching your app's design system.
3. **Log what your blocs do** —
   [`structured_log_bloc`](#4-optional-log-your-blocs-structured_log_bloc),
   a `BlocObserver` for apps built on `bloc`/`flutter_bloc`.
4. **Log your HTTP calls** —
   [`structured_log_dio` or `structured_log_http_client`](#5-optional-log-your-http-calls),
   for apps that talk to their backend through `dio` or `package:http`.
5. **Log navigation** —
   [`structured_log_go_router`](#6-optional-log-navigation-structured_log_go_router),
   for Flutter apps routed with `go_router`.
6. **Log the DI container** —
   [`structured_log_cherrypick`](#7-optional-log-the-di-container-structured_log_cherrypick),
   for apps wired with `cherrypick`.
7. **Also ship those logs to a server** —
   [`structured_log_http`](#8-optional-also-ship-logs-to-a-server), a
   thin add-on `LogSink` output; covered briefly here, in full in the
   Developer Guide.

All three viewer skins share the same `structured_log_flutter` core, so
switching from one to another later is a matter of which viewer widget
you import, not a data-layer change.

## 1. Structured logging: `structured_log`

The core library
([`emb/structured_log`](../../emb/structured_log/),
[published on pub.dev](https://pub.dev/packages/structured_log)):

```yaml
dependencies:
  structured_log: ^0.2.0
```

```dart
import 'package:structured_log/structured_log.dart';

void main() {
  final log = getLogger();
  log.info('user_login', context: {'user_id': 42, 'ip': '127.0.0.1'});
}
```

`bind()` attaches context to a logger immutably (returns a new
instance); `withCorrelation()` binds a fixed, typed set of correlation
fields (`session_id`, `request_id`, `connection_generation`,
`tool_call_id`, `message_id`, `operation_id`) that both
`structured_log_server`'s query filters and the viewer widgets below
understand natively — prefer these over ad-hoc context keys with the
same meaning, so a request can be traced end to end by one of these ids
rather than a field name that happens to match by convention:

```dart
final log = getLogger().withCorrelation(requestId: 'req-42');
log.info('request_started');
log.error('request_failed', context: {'status': 500});
```

Six levels, least to most severe: `trace` < `debug` < `info` <
`warning` < `error` < `critical`. Multiple outputs, each filtered
independently by level or category, is a normal setup — for example a
colored console sink alongside the in-app viewer sink from the next
section:

```dart
StructlogConfiguration.configure(sinks: [
  LogSink(name: 'console', output: coloredConsoleOutput),
  LogSink(name: 'viewer', output: buffer.capture, minLevel: LogLevel.debug),
]);
```

If entries can carry credentials — a header map, a request body, a
config dump — add the redaction processor while you are wiring this up,
because a secret that reaches a sink is already out:

```dart
StructlogConfiguration.configure(
  processors: [redactKeys(), dropNullValues],  // before any renderer
);
```

`redactKeys()` replaces `password`, `token`, `authorization` and the rest
of `defaultSensitiveKeys` at any depth, and takes your own names or
predicates where those are not enough.

Full API — processors, multi-sink routing, file and rotating-file
output — in
[`emb/structured_log/README.md`](../../emb/structured_log/README.md).

## 2. A headless viewer core: `structured_log_flutter`

If you want to build your own log-viewing UI rather than use one of the
ready-made skins in the next section,
[`structured_log_flutter`](../../emb/structured_log_flutter/) is the
piece to build on — a bounded `LogBuffer` (an `OutputFunction` you plug
into a `LogSink`, holding the most recent entries in memory) and a
`LogViewerController` (filtering by level/category/search text, pause,
clear). It doesn't draw anything itself and isn't tied to any design
system:

```yaml
dependencies:
  structured_log_flutter: ^0.1.0
```

```dart
final buffer = LogBuffer();
final controller = LogViewerController(buffer);

StructlogConfiguration.configure(sinks: [
  LogSink(name: 'viewer', output: buffer.capture),
]);
```

`logLevelColor()` — the one piece of visual opinion this package holds
(a `LogLevel` → `Color` mapping, shared by all three skins below) — is
exported too, if you want visual consistency with them without using
one directly. Full API:
[`emb/structured_log_flutter/README.md`](../../emb/structured_log_flutter/README.md).

## 3. A ready-made skin

Three widgets sit on top of `structured_log_flutter`, one per design
system — pick the one matching your app, not your platform (any of the
three runs on any Flutter target):

| Package | Design system | Narrow-screen behavior |
|---|---|---|
| [`structured_log_material`](../../emb/structured_log_material/) | Material 3 | list, tap opens a modal bottom sheet |
| [`structured_log_fluent`](../../emb/structured_log_fluent/) | Fluent UI (WinUI-style) | list, tap opens the detail pane with a back control |
| [`structured_log_cupertino`](../../emb/structured_log_cupertino/) | Cupertino (iOS-style) | list, tap pushes a detail screen (`CupertinoPageRoute`) |

All three master-detail split above their own narrow-width breakpoint
(list and detail panel side by side) and collapse to the pattern above
below it — measured against their own width via `LayoutBuilder`, not
the window's, so an embedded panel behaves correctly regardless of how
wide the surrounding app is.

```yaml
dependencies:
  structured_log_flutter: ^0.1.0
  structured_log_material: ^0.1.0   # or _fluent / _cupertino
```

```dart
import 'package:structured_log_material/structured_log_material.dart';   // or _fluent / _cupertino

// Full screen:
Navigator.of(context).push(MaterialPageRoute(
  builder: (_) => MaterialLogViewerPage(controller: controller),
));

// Or embedded in existing chrome (a side panel, a tab, ...):
MaterialLogViewer(controller: controller)
```

`controller` is the same `LogViewerController` from the previous
section — the skin is purely presentational. Each package has a
runnable web example under its own `example/` directory, and its own
README covers the full widget API:
[`structured_log_material`](../../emb/structured_log_material/README.md),
[`structured_log_fluent`](../../emb/structured_log_fluent/README.md),
[`structured_log_cupertino`](../../emb/structured_log_cupertino/README.md).

## 4. Optional: log your blocs: `structured_log_bloc`

If the app keeps its logic in blocs and cubits
([`bloc`](https://pub.dev/packages/bloc) /
[`flutter_bloc`](https://pub.dev/packages/flutter_bloc)),
[`structured_log_bloc`](../../emb/structured_log_bloc/) logs what every one
of them does — creation, events, state changes, errors, closing — through
the sinks configured above, the in-app viewer included:

```yaml
dependencies:
  structured_log: ^0.2.1
  structured_log_bloc:
    path: ../structured_log_bloc   # not yet on pub.dev (0.1.0-dev.0) — path or git dependency
```

```dart
StructlogConfiguration.configure(sinks: [
  LogSink(name: 'console', output: coloredConsoleOutput),
]);
Bloc.observer = StructuredLogBlocObserver();
```

Every entry carries `category: 'bloc'`, so the viewer's category filter
separates bloc traffic from the rest, and a `LogSink` with
`categories: {'bloc'}` can route it on its own. The package depends on
`package:bloc` only — `flutter_bloc` re-exports the same `Bloc.observer` —
so it needs nothing Flutter-specific.

**States and events are logged through `toString()` by default.** If they
can carry passwords, tokens or personal data, pass a `describe` that
withholds them — see the package's
[README](../../emb/structured_log_bloc/README.md#keeping-secrets-out-of-the-log),
which also lists every entry it writes and how to tune levels per hook.

## 5. Optional: log your HTTP calls

Two packages, one per HTTP client, with the same entries
(`http_request`, then `http_response` or `http_error`, paired by
`http_request_id`), the same levels by status code and the same redaction.
Pick the one matching the client the app already uses.

### `dio`: `structured_log_dio`

If the app talks to its backend through [`dio`](https://pub.dev/packages/dio),
[`structured_log_dio`](../../emb/structured_log_dio/) logs every request
and how it ended — response, error, timeout, cancellation — with the
duration and a level that follows the status code:

```yaml
dependencies:
  structured_log: ^0.2.1
  structured_log_dio:
    path: ../structured_log_dio   # not yet on pub.dev (0.1.0-dev.0) — path or git dependency
```

```dart
final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'))
  ..interceptors.add(StructuredLogDioInterceptor()); // add it last
```

Entries carry `category: 'http'`, next to the blocs' `bloc`, so the viewer
can show either on its own. Headers and bodies are not logged until you
turn them on, and `Authorization`, cookies and token-like query
parameters are redacted — but a body, once on, is logged as it is; see
the package's
[README](../../emb/structured_log_dio/README.md#keeping-secrets-out-of-the-log)
before turning bodies on for login or token calls.

### `package:http`: `structured_log_http_client`

`package:http` has no interceptors, so
[`structured_log_http_client`](../../emb/structured_log_http_client/) is a
client that wraps the one you already use — `IOClient`, `BrowserClient`,
`cupertino_http`, a `RetryClient` — and logs every call it passes through:

```yaml
dependencies:
  structured_log: ^0.2.1
  structured_log_http_client:
    path: ../structured_log_http_client   # not yet on pub.dev (0.1.0-dev.0) — path or git dependency
```

```dart
final client = StructuredLogHttpClient(http.Client());
await client.get(Uri.parse('https://api.example.com/items'));
```

`package:http` does not throw on a status code, so a 404 is an
`http_response` at `warning`. With `logResponseBody` on, the body is not
buffered — it reaches your code as it arrives — and the response entry is
written once the body has been read; see the package's
[README](../../emb/structured_log_http_client/README.md#what-gets-logged).
Not to be confused with `structured_log_http` in the next section, which
*sends* logs to a server.

## 6. Optional: log navigation: `structured_log_go_router`

If the app is routed with [`go_router`](https://pub.dev/packages/go_router),
[`structured_log_go_router`](../../emb/structured_log_go_router/) logs
every navigation — the location, its route pattern (`/users/:id`) and the
previous location — so the log says which screen the user was on when
something went wrong:

```yaml
dependencies:
  structured_log: ^0.2.1
  structured_log_go_router:
    path: ../structured_log_go_router   # not yet on pub.dev (0.1.0-dev.0) — path or git dependency
```

```dart
final routeLog = StructuredLogGoRouter();
final router = GoRouter(
  routes: [/* ... */],
  redirect: routeLog.redirect(authRedirect), // optional: logs redirects too
);
routeLog.attach(router);
```

Entries carry `category: 'navigation'`, next to `bloc` and `http`.
Token-like query parameters — including an OAuth callback's `code` and a
`#access_token=...` fragment — are redacted; path parameters are not, so
see the package's
[README](../../emb/structured_log_go_router/README.md#keeping-secrets-out-of-the-log)
if a route carries something sensitive in its path.

## 7. Optional: log the DI container: `structured_log_cherrypick`

If the app is wired with [`cherrypick`](https://pub.dev/packages/cherrypick),
[`structured_log_cherrypick`](../../emb/structured_log_cherrypick/) logs
what the container does — scopes opening and closing, modules installed,
dependency cycles, resolve errors — which is how a wiring that silently did
not happen shows up:

```yaml
dependencies:
  structured_log: ^0.2.1
  structured_log_cherrypick:
    path: ../structured_log_cherrypick   # not yet on pub.dev (0.1.0-dev.0) — path or git dependency
```

```dart
// Before the first scope: a scope takes the global observer when created.
CherryPick.setGlobalObserver(StructuredLogCherryPickObserver());
```

Entries carry `category: 'di'`. An instance is never logged — only the
name and type it is bound under — so a container full of clients and token
stores is safe to observe. The per-resolve reports are off by default; see
the package's
[README](../../emb/structured_log_cherrypick/README.md#what-gets-logged)
for turning them on and for what the container itself does and does not
report.

## 8. Optional: also ship logs to a server

Everything above is entirely local — no network, no server. If you also
want these logs collected centrally (searchable across restarts,
shared across a team, retained on a schedule),
[`structured_log_http`](../../emb/structured_log_http/) is a `LogSink`
output that ships entries to a `structured_log_server` instance over
HTTP, batched with retry and a bounded buffer:

```yaml
dependencies:
  structured_log: ^0.2.0
  structured_log_http:
    path: ../structured_log_http   # not yet on pub.dev (0.1.0-dev.0) — path or git dependency
```

```dart
final output = HttpLogOutput(
  serverUrl: 'https://logs.example.com',
  projectSecretKey: 'slk_...',
);

StructlogConfiguration.configure(sinks: [
  LogSink(name: 'server', output: output),
]);
```

This is the same package covered in full in the Developer Guide's
[Sending logs to the server](developer-guide.md#sending-logs-to-the-server)
section — getting a project secret key, what batching/retry/eviction
you get for free, and how to keep a local sink (console, or the viewer
above) running alongside it. Deploying the server itself is covered in
the [Administrator / DevOps Guide](admin-guide.md).

## Where to go next

- Each package's own README — the full API reference, verbatim:
  [`structured_log`](../../emb/structured_log/README.md),
  [`structured_log_flutter`](../../emb/structured_log_flutter/README.md),
  [`structured_log_material`](../../emb/structured_log_material/README.md),
  [`structured_log_fluent`](../../emb/structured_log_fluent/README.md),
  [`structured_log_cupertino`](../../emb/structured_log_cupertino/README.md),
  [`structured_log_bloc`](../../emb/structured_log_bloc/README.md),
  [`structured_log_dio`](../../emb/structured_log_dio/README.md),
  [`structured_log_http_client`](../../emb/structured_log_http_client/README.md),
  [`structured_log_go_router`](../../emb/structured_log_go_router/README.md),
  [`structured_log_cherrypick`](../../emb/structured_log_cherrypick/README.md),
  [`structured_log_http`](../../emb/structured_log_http/README.md).
- [Developer Guide](developer-guide.md) — once a server is involved:
  the ingestion HTTP endpoint directly, querying logs back out,
  live-tailing programmatically, and authenticating as a person.
- [Contributor Guide](contributor-guide.md) — if you want to change one
  of these packages rather than just use it.
