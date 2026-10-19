# structured_log_riverpod

[![CI](https://github.com/pese-git/structured_log/actions/workflows/ci.yml/badge.svg)](https://github.com/pese-git/structured_log/actions/workflows/ci.yml)

*Читать на [русском](README.ru.md).*

**See what every Riverpod provider in your app did — created, updated,
failed, removed — as structured log entries, with one line of setup.**

Documentation: [structured-log.openidealab.com](https://structured-log.openidealab.com).

## Why

"Why is this screen empty?" is a question a Riverpod app keeps asking, and
the answer is usually a provider that failed, or one that never got the value
you expected. Without a record you reproduce the bug under a debugger or add
a `ProviderObserver` that `print`s — and on a user's device you can do
neither.

`StructuredLogRiverpodObserver` keeps the record for you. Passed to the
container once, it writes the creation, updates, failures and removal of every
provider as `structured_log` entries — with the provider's name, its family
argument and the values involved as separate fields, so you can filter the
story of one provider out of everything else.

## Features

### Coverage

- **One line to install** — `ProviderScope(observers: [StructuredLogRiverpodObserver()])`.
- **The whole life of a provider** — creation, updates, failures with stack
  traces, removal.
- **Providers told apart** — by `name`, or by type when there is none; a
  family's argument is a field of its own.
- **Each failure once** — Riverpod reports a failing future twice, as an
  update to `AsyncError` and as a failure; the observer logs the failure and
  skips the update.
- **Works with `flutter_riverpod` and `hooks_riverpod` as is** — depends on
  `package:riverpod` only, which both are built on, so it also runs in pure
  Dart.

### Control

- **Its own category** — every entry carries `category: 'riverpod'`, so a
  `LogSink` can route provider traffic separately and the in-app log viewer
  offers it as a filter.
- **A level per hook** — or `null` to turn a hook off, usually the updates.
- **A filter** — leave noisy providers out of the log entirely.
- **Values under your control** — values and family arguments go through a
  describer you can replace, to keep secrets out of the log or hand
  `redactKeys` a map.

### Safety

- **Never breaks a provider** — a `toString()` or describer that throws costs
  the entry its values, and a filter that throws costs the entry, but neither
  reaches the code that changed the state.
- **Costs nothing when off** — a hook that is off, a provider that is
  filtered out or a level no sink takes never has its value described.

## Where it fits

The observer needs nothing but
[`structured_log`](https://pub.dev/packages/structured_log) — no server, no
Flutter. Its entries flow to whatever sinks you have configured: the
console, a file, an in-app log viewer
([`structured_log_material`](https://pub.dev/packages/structured_log_material),
[`structured_log_fluent`](https://pub.dev/packages/structured_log_fluent) or
[`structured_log_cupertino`](https://pub.dev/packages/structured_log_cupertino)),
where the `riverpod` category becomes a filter, or a self-hosted
`structured_log_server` through
[`structured_log_remote_sync`](https://pub.dev/packages/structured_log_remote_sync).
It is one of nine adapters that log what your app's libraries already do;
the whole project is at
[structured-log.openidealab.com](https://structured-log.openidealab.com).

## Installation

**Riverpod 3 only.** The observer hooks of Riverpod 2.x have other signatures,
and one class cannot override both; for 2.x this package does not work.

Published on pub.dev as a pre-release:

```yaml
dependencies:
  flutter_riverpod: ^3.0.0 # or riverpod: ^3.0.0
  structured_log: ^0.3.0
  structured_log_riverpod: ^0.1.0-dev.1
```

## Quick Start

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_riverpod/structured_log_riverpod.dart';

void main() {
  StructlogConfiguration.configure(
    sinks: [LogSink(name: 'console', output: coloredConsoleOutput)],
  );

  runApp(
    ProviderScope(
      observers: [StructuredLogRiverpodObserver()],
      child: const MyApp(),
    ),
  );
}
```

In pure Dart pass the same observer to the container:
`ProviderContainer(observers: [StructuredLogRiverpodObserver()])`.

A named `counter` provider that is read and then set to `1` logs:

```text
[2026-10-13T22:27:13.862226Z] DEBUG: provider_added {"logger":"riverpod","category":"riverpod","provider":"counter","value":"0","value_type":"int"}
[2026-10-13T22:27:13.875054Z] DEBUG: provider_updated {"logger":"riverpod","category":"riverpod","provider":"counter","previous_value":"0","value":"1","value_type":"int"}
```

A failing `FutureProvider` named `profile` logs once, as an error:

```text
[2026-10-13T22:27:13.884681Z] ERROR: provider_failed {"logger":"riverpod","category":"riverpod","provider":"profile","error":"Bad state: offline","error_type":"StateError","stack_trace":"#0 ..."}
```

See [example/main.dart](example/main.dart) for a runnable version
(`dart run example/main.dart`).

## What gets logged

Every entry carries `category` (`riverpod` by default), `logger` (`riverpod`
by default) and `provider`: the provider's `name`, or its type when it has no
name. For a family, `provider_argument` holds the argument.

| Hook                 | `event`             | Default level | Fields |
|----------------------|---------------------|---------------|--------|
| `didAddProvider`     | `provider_added`    | `debug`       | `value`, `value_type` |
| `didUpdateProvider`  | `provider_updated`  | `debug`       | `previous_value`, `value`, `value_type` |
| `providerDidFail`    | `provider_failed`   | `error`       | `error`, `error_type`, `stack_trace` |
| `didUnmountProvider` | `provider_disposed` | `debug`       | — |

A provider that throws while building is logged as `provider_added` with no
`value` and `value_type: Null`, then as `provider_failed`.

`provider_disposed` is written when a provider is **removed from memory**, for
example an `autoDispose` provider that lost its last listener. A provider that
merely rebuilds — a dependency changed, `refresh`, `invalidate` — is not
disposed, and writes no entry of that name. The hook behind it,
`didUnmountProvider`, exists from `riverpod` **3.3.2**: on 3.0.0–3.2.1 this
entry is not written at all, and nothing tells you so. The other three
entries are the same on every 3.x. If you need `provider_disposed`, depend on
`riverpod: ^3.3.2`.

Mutations (`mutationStart` and friends, new in Riverpod 3) are not logged:
their API is marked experimental.

## Keeping secrets out of the log

**Values and family arguments are logged through `toString()` by default**
(cut to 1000 characters). If they can carry passwords, tokens or personal
data — and especially if the log leaves the device through
`structured_log_remote_sync` — pass a `describe` that withholds them.
Returning `null` drops the value and keeps its type:

```dart
StructuredLogRiverpodObserver(
  describe: (value) => switch (value) {
    Session() || Credentials() => null,
    _ => describeRiverpodValue(value),
  },
)
```

The same `describe` sees the family argument, which is often a user id or a
token, so one function covers both. To log types only, everywhere:
`describe: (_) => null`.

A `describe` can also return a **map** instead of a string. A map stays a
structure in the entry, so a `redactKeys` processor reaches its fields, as it
reaches any other field. A string from `toString()` is opaque to it:

```dart
StructlogConfiguration.configure(processors: [redactKeys(), dropNullValues]);

StructuredLogRiverpodObserver(
  describe: (value) => switch (value) {
    Session(:final user, :final token) => {'user': user, 'token': token},
    _ => describeRiverpodValue(value),
  },
)
// value: {"user": "u", "token": "***"}
```

The error of `provider_failed` is not run through `describe`: it is written
by `structured_log` itself, as `error`, `error_type` and `stack_trace`.

## Configuration

```dart
StructuredLogRiverpodObserver(
  // Which hooks are logged, and at what level; null turns one off.
  levels: const RiverpodLogLevels(
    added: LogLevel.trace,
    updated: null, // a provider bound to a text field updates all the time
  ),
  // Leave noisy providers out.
  filter: (provider) => provider.name != 'ticker',
  category: 'state',
)
```

## API Reference

| Symbol | Description |
|---|---|
| `StructuredLogRiverpodObserver({logger, loggerName, category, levels, describe, filter})` | The observer, a `final class` extending `ProviderObserver`. Without `logger`, it calls `getLogger(loggerName)` on every hook, so a later `StructlogConfiguration.configure` reaches it too. `category: null` binds no category. |
| `RiverpodLogLevels({added, updated, failed, disposed})` | A `LogLevel?` per hook; `null` turns the hook off. |
| `RiverpodValueDescriber` | `Object? Function(Object? value)` — turns a value or a family argument into an entry value; `null` omits the field. |
| `describeRiverpodValue(value)` | The default describer: `toString()`, cut to `defaultRiverpodValueMaxLength` (1000) characters; a throwing `toString()` becomes a placeholder. |

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

## License

MIT — see [LICENSE](LICENSE).
