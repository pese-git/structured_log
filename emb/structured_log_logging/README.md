# structured_log_logging

[![CI](https://github.com/pese-git/structured_log/actions/workflows/ci.yml/badge.svg)](https://github.com/pese-git/structured_log/actions/workflows/ci.yml)

*Читать на [русском](README.ru.md).*

**Bring the logs of every library that writes through `package:logging` into
`structured_log` — the same sinks, in-app viewer and server as your own
entries — with one line of setup.**

Documentation: [structured-log.openidealab.com](https://structured-log.openidealab.com).

## Why

`package:logging` is what most of the Dart ecosystem logs through: database
drivers, code generators, HTTP stacks, plenty of application libraries. Their
records go nowhere on their own — only to whoever listens on
`Logger.root.onRecord`, usually a `print` in `main`. So they never reach your
log file, the in-app log viewer or a self-hosted `structured_log_server`, and
the one log you look at after an incident is missing exactly the driver that
failed.

`StructuredLogLoggingBridge` closes that gap. Attached once, it writes every
`package:logging` record as a `structured_log` entry, so it is routed,
filtered, redacted and shipped like any other — without touching the
libraries that wrote it.

## Features

### Coverage

- **One line to attach** — `StructuredLogLoggingBridge().attach()`.
- **Every library at once** — it listens on `Logger.root`, the one stream
  every `package:logging` record goes through.
- **Entries in the shape of your own** — an error and a stack trace become
  `error`, `error_type` and `stack_trace`, exactly as with
  `BoundLogger.error`.
- **Levels by value** — `FINE` is `debug`, `SEVERE` is `error`, and a custom
  `Level('NOTICE', 850)` lands at `info` without any setup.

### Control

- **Its own category** — every entry carries `category: 'logging'`, so a
  `LogSink` can take, or leave, everything other libraries wrote.
- **Your level mapping** — replace it, or return `null` to leave a level out.
- **A filter** — leave noisy loggers out entirely.
- **Fields of your own** — add a request id kept in the record's zone, or
  anything else a record carries.

### Safety

- **Never throws into the caller** — it runs inside the library's own
  `Logger.log` call. A filter or level mapping that throws costs the record
  — it is where you keep records out, so the bridge errs on that side; a
  context callback that throws costs only its fields, and the entry names
  its type in `bridge_failed`.
- **Leaves `package:logging` alone** — it never changes a logger's level or
  `hierarchicalLoggingEnabled`.

## Where it fits

The bridge needs nothing but
[`structured_log`](https://pub.dev/packages/structured_log) and
`package:logging` — no server, no Flutter, and it works on the web. Its
entries flow to whatever sinks you have configured: the console, a file, an
in-app log viewer
([`structured_log_material`](https://pub.dev/packages/structured_log_material),
[`structured_log_fluent`](https://pub.dev/packages/structured_log_fluent) or
[`structured_log_cupertino`](https://pub.dev/packages/structured_log_cupertino)),
where the `logging` category becomes a filter, or a self-hosted
`structured_log_server` through
[`structured_log_remote_sync`](https://pub.dev/packages/structured_log_remote_sync).
It is one of six adapters that log what your app's libraries already do;
the whole project is at
[structured-log.openidealab.com](https://structured-log.openidealab.com).

## Installation

Published on pub.dev as a pre-release:

```yaml
dependencies:
  logging: ^1.2.0
  structured_log: ^0.3.0
  structured_log_logging: ^0.1.0-dev.1
```

## Quick Start

```dart
import 'package:logging/logging.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_logging/structured_log_logging.dart';

void main() {
  StructlogConfiguration.configure(
    sinks: [LogSink(name: 'console', output: coloredConsoleOutput)],
  );
  Logger.root.level = Level.ALL; // see "Which records arrive" below
  StructuredLogLoggingBridge().attach();

  // ...
}
```

A database driver that writes through `package:logging` then logs:

```text
[2026-10-05T09:39:05.575330Z] INFO: connection opened {"logger":"db","category":"logging"}
[2026-10-05T09:39:05.578816Z] DEBUG: query took 3 ms {"logger":"db","category":"logging"}
[2026-10-05T09:39:05.579002Z] ERROR: query failed {"logger":"db","category":"logging","error":"Bad state: connection closed","error_type":"StateError"}
```

See [example/main.dart](example/main.dart) for a runnable version
(`dart run example/main.dart`).

## What gets logged

Each `LogRecord` becomes one entry:

| Record | Entry |
|---|---|
| `message` | `event` |
| `loggerName` | `logger` (`root` for the root logger) |
| `level` | `level`, mapped as below |
| `error` | `error` (its `toString()`) and `error_type` |
| `stackTrace` | `stack_trace` |
| — | `category: 'logging'` |

The record's `object` is not written: its `toString()` already is the
message. Neither are its `time`, `sequenceNumber` or `zone`; `structured_log`
stamps its own `timestamp`, and `context` adds whatever else you want.

| `Level.value` | Level | Standard levels |
|---|---|---|
| below 500 | `trace` | `FINEST`, `FINER` |
| 500–699 | `debug` | `FINE` |
| 700–899 | `info` | `CONFIG`, `INFO` |
| 900–999 | `warning` | `WARNING` |
| 1000–1199 | `error` | `SEVERE` |
| 1200 and up | `critical` | `SHOUT` |

With `recordStackTraceAtLevel` set, `package:logging` adds a stack trace of
its own and, when there is no error, the string `autogenerated stack trace
for …` in its place. The bridge keeps the stack trace and leaves that string
out.

## Which records arrive

The bridge sees only the records `package:logging` creates, and
`Logger.root` creates `INFO` and above by default — a `fine(...)` call below
that is dropped before any listener hears of it. The bridge does not change
that for you: lowering `Logger.root.level` makes every library in the app
build the messages it was skipping, which is your call, not the bridge's.

```dart
Logger.root.level = Level.ALL;
```

A sink's own `minLevel` then decides what is kept, as for any entry.

## Keeping secrets out of the log

Libraries put whatever they like in a message: a URL with its query, an SQL
statement with its arguments, a header. A message is the entry's `event`, a
plain string, so `redactKeys` cannot look inside it. Leave out what you
don't trust:

```dart
StructuredLogLoggingBridge(
  // A logger that is too talkative or too revealing.
  filter: (record) => record.loggerName != 'http.wire',
  // A level you never want, from anyone.
  levelOf: (level) => level < Level.FINE ? null : defaultLogLevelOf(level),
).attach();
```

and, for what stays, a processor of your own that rewrites `event` where
`category` is `logging`.

## Logging from a sink

`package:logging` publishes each record synchronously, and its stream does
not start a new record while it is still handing out the current one. The
bridge delivers *during* that hand-out, so code run by a `structured_log`
sink or processor that itself writes through `package:logging` — a sink
built on a client that logs through it, say — gets a `StateError` from that
call. The bridge cannot loop because of it, but the library making the call
sees the exception. Write from a sink asynchronously, or not through
`package:logging`.

## Configuration

```dart
StructuredLogLoggingBridge(
  // Another logger than Logger.root; only matters with
  // hierarchicalLoggingEnabled, where each logger has a stream of its own.
  source: Logger('app'),
  // Your level mapping; null leaves a level out.
  levelOf: defaultLogLevelOf,
  // Leave records out.
  filter: (record) => !record.loggerName.startsWith('build'),
  // null writes no category.
  category: 'libraries',
  // Extra fields, such as a request id kept in the record's zone.
  context: (record) => {'request_id': record.zone?[#requestId]},
).attach();
```

`attach` again does nothing while attached; `detach` stops, and `attach`
starts again.

## API Reference

| Symbol | Description |
|---|---|
| `StructuredLogLoggingBridge({source, levelOf, filter, category, context})` | The bridge. It calls `getLogger(loggerName)` for each record, so a later `StructlogConfiguration.configure` reaches it too. `category: null` writes no category. |
| `attach()` / `detach()` / `isAttached` | Start bridging `source`'s records, stop, or ask which. |
| `LogLevelOf` | `LogLevel? Function(Level level)` — the level a record is written at; `null` leaves it out. |
| `defaultLogLevelOf(level)` | The default mapping, by `Level.value`. |

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
- [`structured_log_cherrypick`](https://pub.dev/packages/structured_log_cherrypick) — observer for the `cherrypick` DI container
- [`structured_log_drift`](https://pub.dev/packages/structured_log_drift) — drift `QueryInterceptor` that logs queries, failures and transactions

## License

MIT — see [LICENSE](LICENSE).
