# structured_log_auto_route

[![CI](https://github.com/pese-git/structured_log/actions/workflows/ci.yml/badge.svg)](https://github.com/pese-git/structured_log/actions/workflows/ci.yml)

*Читать на [русском](README.ru.md).*

**See every screen your `auto_route` app opened, closed and switched between
as structured log entries — with tokens in the location redacted, and one
line of setup.**

Documentation: [structured-log.openidealab.com](https://structured-log.openidealab.com).

## Why

"How did the user get here?" is the first question about any error on a
screen, and the answer is the path they took. Without a record you reproduce
the bug by hand or add a `NavigatorObserver` that `print`s — and on a user's
device you can do neither.

`StructuredLogAutoRouteObserver` keeps the record for you. Passed to the
router once, it writes every screen that was opened, closed or removed and
every tab switch as `structured_log` entries — with the route's name, its
pattern and its location as separate fields, so you can filter the story of
one screen out of everything else. The same ring of entries is what the
in-app log viewer shows and what `structured_log_server` stores.

## Features

### Coverage

- **One line to install** — `appRouter.config(navigatorObservers: () => [StructuredLogAutoRouteObserver()])`.
- **Pushes, pops, removals, tabs** — what `auto_route` tells a
  `NavigatorObserver`, plus the tab hooks of `AutoRouterObserver`.
- **Screens told apart** — by name (`UserRoute`), by pattern
  (`/user/:id`) and by where they actually are (`/user/7?tab=posts`).
- **Nested routes** — a screen inside a shell is located below its parents.
- **Works with generated and hand-written routers** — it depends on
  `package:auto_route` only.

### Control

- **Its own category** — every entry carries `category: 'navigation'`, so a
  `LogSink` can route navigation separately and the in-app log viewer offers
  it as a filter. `structured_log_go_router` uses the same one.
- **A level per event** — or `null` to turn an event off.
- **A filter** — leave noisy screens out of the log entirely.

### Safety

- **Tokens never reach the log** — the values of `token`, `code`,
  `password` and the rest of a configurable list are replaced with `REDACTED`
  in path parameters, in the query and in an OAuth-style fragment.
- **Never breaks navigation** — a filter or a logger that throws costs the
  entry, not the navigation.
- **Costs nothing when off** — an event that is off, a screen that is filtered
  out or a level no sink takes is never described.

## Where it fits

The observer needs nothing but
[`structured_log`](https://pub.dev/packages/structured_log) — no server. Its
entries flow to whatever sinks you have configured: the console, a file, an
in-app log viewer
([`structured_log_material`](https://pub.dev/packages/structured_log_material),
[`structured_log_fluent`](https://pub.dev/packages/structured_log_fluent) or
[`structured_log_cupertino`](https://pub.dev/packages/structured_log_cupertino)),
where the `navigation` category becomes a filter, or a self-hosted
`structured_log_server` through
[`structured_log_remote_sync`](https://pub.dev/packages/structured_log_remote_sync).
It is one of ten adapters that log what your app's libraries already do;
the whole project is at
[structured-log.openidealab.com](https://structured-log.openidealab.com).

## Installation

Works with `auto_route` 10 and 11. For `go_router` use
[`structured_log_go_router`](https://pub.dev/packages/structured_log_go_router).

Published on pub.dev as a pre-release:

```yaml
dependencies:
  auto_route: ">=10.0.0 <12.0.0"
  structured_log: ^0.3.0
  structured_log_auto_route: ^0.1.0-dev.1
```

## Quick Start

```dart
import 'package:flutter/material.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_auto_route/structured_log_auto_route.dart';

void main() {
  StructlogConfiguration.configure(
    sinks: [LogSink(name: 'console', output: coloredConsoleOutput)],
  );

  final appRouter = AppRouter();
  runApp(
    MaterialApp.router(
      routerConfig: appRouter.config(
        navigatorObservers: () => [StructuredLogAutoRouteObserver()],
      ),
    ),
  );
}
```

`navigatorObservers` is a builder: `auto_route` asks it for the observers of
every navigator it creates, nested ones included, so return a **new** observer
or share one — the observer keeps no state, so either is fine.

Opening a user screen with a token in the query, replacing it with settings
and going back logs:

```text
[2026-10-19T07:11:40.802293Z] INFO: route_pushed {"logger":"router","category":"navigation","route":"User","route_path":"/user/:id","location":"/user/42?token=REDACTED&tab=posts","previous_route":"Home","previous_location":"/"}
[2026-10-19T07:11:40.904616Z] INFO: route_pushed {"logger":"router","category":"navigation","route":"Settings","route_path":"/settings","location":"/settings","previous_route":"User","previous_location":"/user/42"}
[2026-10-19T07:11:40.905216Z] INFO: route_removed {"logger":"router","category":"navigation","route":"User","route_path":"/user/:id","location":"/user/42?token=REDACTED&tab=posts","previous_route":"Home","previous_location":"/"}
```

See [example/main.dart](example/main.dart) for a runnable version.

## What gets logged

Every entry carries `category` (`navigation` by default), `logger` (`router`
by default) and the screen it is about:

- `route` — the route's name, such as `User`;
- `route_path` — its path pattern, such as `/user/:id`;
- `location` — where it actually is, such as `/user/42?tab=posts`, with
  sensitive values redacted. Nested routes are located below their parents.

| Event | When | Default level | Also carries |
|---|---|---|---|
| `route_pushed` | a screen was opened | `info` | `previous_route`, `previous_location` |
| `route_popped` | a screen was closed | `info` | the screen that shows again, as `previous_*` |
| `route_removed` | a screen left the stack without a pop | `info` | `previous_*` |
| `route_replaced` | the navigator reported a replacement itself | `info` | the old screen, as `previous_*` |
| `route_tab_changed` | a tab of a `TabsRouter` was activated or switched to | `info` | `tab_index`, `tab_event` (`init` or `change`), `previous_route` |

`previous_location` is a **path only**, without query or fragment. `auto_route`
keeps the query of the navigation in progress on the router, not on each
route, so a neighbour's own query cannot be told from the one that is moving.

A `replace` is not `route_replaced`: the stack is page-based, and the
navigator reports a push of the new screen and a removal of the old one. You
will see `route_pushed` followed by `route_removed`. `route_replaced` is
there for a version that reports it.

A tab entry names the tab by its own path (`/feed`), not below its shell: the
tab hooks do not carry the shell. Whether a first visit to a second tab is
`init` or `change` is `auto_route`'s call and differs between 10 and 11.

A screen opened outside the router — a dialog, a bottom sheet — is logged by
its settings name or its type, and has no `route_path` or `location`. The
filter does not see it.

### What is not logged

An observer sees what the `Navigator` sees. Three things never reach it:

- **A route updated in place.** `navigatePath('/user/9')` while `/user/7` is
  open keeps the same screen and changes its parameters; the navigator is not
  told, so there is no entry.
- **A path no route matches.** `auto_route` reports it to the `onFailure` of
  that one call, nowhere global.
- **What a guard decides.** `AutoRouteGuard` runs before the navigator is
  involved.

## Keeping secrets out of the log

The values of these names are replaced with `REDACTED`, compared without
regard to case, wherever they appear — a path parameter, a query parameter, a
fragment written as a query (`#access_token=...`):

`access_token`, `refresh_token`, `id_token`, `token`, `api_key`, `apikey`,
`password`, `client_secret`, `code`.

The pattern in `route_path` carries no values and is logged as it is. Replace
the list with `redactedParameters`:

```dart
StructuredLogAutoRouteObserver(
  redactedParameters: {...defaultRedactedParameters, 'session'},
)
```

Names must be lower case. Nothing else about a route is logged: `extra`,
`args` and the page's widgets are never read.

## Configuration

```dart
StructuredLogAutoRouteObserver(
  // Which events are logged, and at what level; null turns one off.
  levels: const RouteLogLevels(
    pushed: LogLevel.debug,
    popped: null,
  ),
  // Leave screens out. A route it rejects is not logged, and does not
  // appear as the neighbour of another.
  filter: (route) => route.name != 'Splash',
  category: 'screens',
)
```

## API Reference

| Symbol | Description |
|---|---|
| `StructuredLogAutoRouteObserver({logger, loggerName, category, levels, redactedParameters, filter})` | The observer, an `AutoRouterObserver`. Without `logger`, it calls `getLogger(loggerName)` on every entry, so a later `StructlogConfiguration.configure` reaches it too. `category: null` binds no category. |
| `RouteLogLevels({pushed, popped, removed, replaced, tabChanged})` | A `LogLevel?` per event; `null` turns the event off. |
| `defaultRedactedParameters` | The default set of names whose values are redacted. |
| `redactedValue` | `'REDACTED'`. |

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
- [`structured_log_riverpod`](https://pub.dev/packages/structured_log_riverpod) — `ProviderObserver` for `riverpod`/`flutter_riverpod`
- [`structured_log_dio`](https://pub.dev/packages/structured_log_dio) — `dio` interceptor that logs HTTP calls
- [`structured_log_http_client`](https://pub.dev/packages/structured_log_http_client) — `package:http` client wrapper that logs HTTP calls
- [`structured_log_go_router`](https://pub.dev/packages/structured_log_go_router) — logs `go_router` navigation
- [`structured_log_cherrypick`](https://pub.dev/packages/structured_log_cherrypick) — observer for the `cherrypick` DI container
- [`structured_log_drift`](https://pub.dev/packages/structured_log_drift) — drift `QueryInterceptor` that logs queries, failures and transactions
- [`structured_log_logging`](https://pub.dev/packages/structured_log_logging) — bridge that routes `package:logging` records into `structured_log`
- [`structured_log_shelf`](https://pub.dev/packages/structured_log_shelf) — `shelf` middleware that logs server requests and gives handlers a logger bound to the `request_id`

## License

MIT — see [LICENSE](LICENSE).
