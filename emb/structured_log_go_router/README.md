# structured_log_go_router

[![CI](https://github.com/pese-git/structured_log/actions/workflows/ci.yml/badge.svg)](https://github.com/pese-git/structured_log/actions/workflows/ci.yml)

*Читать на [русском](README.ru.md).*

**Where your [`go_router`](https://pub.dev/packages/go_router) app goes —
every navigation, redirect and routing error — as a
[`structured_log`](https://pub.dev/packages/structured_log) entry, with the
route pattern next to the location.**

## Why

The first question about most bug reports is *which screen was the user
on, and how did they get there?* The answer is usually missing: navigation
happens inside the router, and a stack trace only shows the widget that
crashed, not the path that led to it.

`StructuredLogGoRouter` listens to a `GoRouter` and writes an entry each
time it settles on a new location — `go`, `push`, `pop`, a deep link, the
browser's back button — with the matched route pattern and where the user
came from. Routing errors are logged too, and redirects once you wrap your
`redirect`. Next to the `bloc` entries from `structured_log_bloc`
and the `http` ones from `structured_log_dio` / `structured_log_http_client`,
this gives a bug report its context: the screen, then the state, then the
call that failed.

## Features

### What you see

- **Every navigation** — `go`, `push`, `pop`, deep links and the browser's
  back button all count; a notification that does not change the location
  is not logged twice.
- **Pattern next to location** — `/users/42` is logged with its route
  `/users/:id` and route name, so screens group without parsing URLs.
- **Where the user came from** — `previous_location` and `previous_route`
  on each navigation after the first.
- **Redirects and routing errors** — wrap `redirect` and `onException` to
  log them too; the not-found page is logged without any wrapping.
- **Its own category** — every entry carries `category: 'navigation'`.

### What stays out

- **Tokens** — token-like query parameters, and the OAuth `code` a sign-in
  callback carries, are redacted, in the query and in an OAuth-style
  fragment (`#access_token=...`).
- **Route state** — `extra` and other state objects are never logged.
- **Screens you choose** — a `filter` leaves out the navigations to a route
  whose path itself is sensitive.

### What doesn't get in the way

- **Attach to any router** — `routeLog.attach(router)`, and `detach()` to
  stop.
- **Never breaks navigation** — a filter that throws costs the entry; a
  wrapped redirect's answer and exceptions reach the router unchanged, and
  a synchronous redirect stays synchronous.
- **Follows reconfiguration** — without an explicit logger it picks up a
  later `StructlogConfiguration.configure`.

## Where it fits

`structured_log_go_router` is one of the integrations around
[`structured_log`](https://pub.dev/packages/structured_log): a Flutter
package that depends on nothing but the core and `go_router`, and writes
through the sinks you have already configured. No server is needed: the
entries go to the console, a file, or the in-app log viewer
([`structured_log_flutter`](https://pub.dev/packages/structured_log_flutter)
with a Material, Fluent or Cupertino skin), and — if you run the
self-hosted `structured_log_server` — to it through
[`structured_log_remote_sync`](https://pub.dev/packages/structured_log_remote_sync),
where your team can follow one user's path through the app next to the
calls it made. More at
[structured-log.openidealab.com](https://structured-log.openidealab.com).

## Installation

Published on pub.dev as a pre-release:

```yaml
dependencies:
  go_router: ">=17.0.0 <19.0.0"
  structured_log: ^0.3.0
  structured_log_go_router: ^0.1.0-dev.3
```

## Quick Start

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_go_router/structured_log_go_router.dart';

void main() {
  StructlogConfiguration.configure(
    sinks: [LogSink(name: 'console', output: coloredConsoleOutput)],
  );

  final routeLog = StructuredLogGoRouter();
  final router = GoRouter(
    routes: [/* ... */],
    redirect: routeLog.redirect(authRedirect), // optional
  );
  routeLog.attach(router);

  runApp(MaterialApp.router(routerConfig: router));
}
```

```text
INFO:  route_changed    {"category":"navigation","location":"/","route":"/","route_name":"home"}
DEBUG: route_redirected {"category":"navigation","from":"/settings","to":"/login"}
INFO:  route_changed    {"category":"navigation","location":"/login","route":"/login","previous_location":"/","previous_route":"/"}
```

[example/main.dart](example/main.dart) is a small app with three screens,
a redirect and a not-found page. The package has no platform folders of its
own, so run it as the `lib/main.dart` of any Flutter app that depends on
this package.

## What gets logged

| Entry              | When | Default level | Fields |
|--------------------|------|---------------|--------|
| `route_changed`    | the router settled on a new location — `go`, `push`, `pop`, a deep link, the browser's back button | `info` | `location`, `route` (the pattern), `route_name` if the route has one; `previous_location`, `previous_route` after the first navigation |
| `route_redirected` | a redirect wrapped with `routeLog.redirect(...)` sent the navigation elsewhere | `debug` | `from`, `to` |
| `route_error`      | a location matched no route, or routing failed | `warning` | `location`, `error` |

`route_error` reaches the log in either of go_router's two error modes:
with `errorBuilder`/`errorPageBuilder` (or neither), `attach` sees the
router land on its error page; with `onException`, the router stays where
it was, so wrap the handler — `onException: routeLog.onException(handler)`.

Only the router's own pages are seen. A dialog or bottom sheet opened with
`showDialog`/`showModalBottomSheet` is not a location and does not appear.

## Keeping secrets out of the log

Locations are logged as they are — path parameters included, since that
is what identifies the screen — with two exceptions:

- the values of `defaultRedactedQueryParameters` — `access_token`,
  `refresh_token`, `id_token`, `token`, `api_key`, `apikey`, `password`,
  `client_secret`, and `code` (the OAuth authorization code a sign-in
  callback carries) — become `REDACTED`, in the query and in a fragment
  shaped like one (`#access_token=...`). Pass `redactedQueryParameters`
  to change the set (lower-case names; compared case-insensitively);
- `extra` and other route state objects are never logged.

If a path parameter itself is sensitive (an email in `/invite/:email`),
leave that route out with `filter`.

## Configuration

```dart
StructuredLogGoRouter(
  // Which entries are logged, and at what level; null turns one off.
  levels: const RouteLogLevels(navigation: LogLevel.debug),
  // Leave a screen out — its navigations only; redirects and errors stay.
  filter: (state) => state.fullPath != '/invite/:email',
  category: 'ui',
);
```

`attach` again to move to another router; `detach` before disposing the
router it is attached to.

## API Reference

| Symbol | Description |
|---|---|
| `StructuredLogGoRouter({logger, loggerName, category, levels, redactedQueryParameters, filter})` | The logger. Without `logger` it calls `getLogger(loggerName)` (`router`) on every entry, so a later `StructlogConfiguration.configure` reaches it too. `category: null` binds no category. |
| `attach(router)` / `detach()` | Start logging a router's navigations — including the location it is already on — or stop. |
| `redirect(inner)` | Wraps a top-level or route-level `GoRouterRedirect`, logging each redirect it makes; a synchronous redirect stays synchronous. |
| `onException(inner)` | Wraps a `GoExceptionHandler`, logging each routing error before handing it on. |
| `RouteLogLevels({navigation, redirect, error})` | A `LogLevel?` per entry; `null` turns it off. |
| `defaultRedactedQueryParameters`, `redactedValue` | The default redaction set and the value (`REDACTED`) that replaces what it matches. |

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
- [`structured_log_cherrypick`](https://pub.dev/packages/structured_log_cherrypick) — observer for the `cherrypick` DI container
- [`structured_log_drift`](https://pub.dev/packages/structured_log_drift) — drift `QueryInterceptor` that logs queries, failures and transactions

## License

See [LICENSE](LICENSE).
