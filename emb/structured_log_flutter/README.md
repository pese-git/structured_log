# structured_log_flutter

*Читать на [русском](README.ru.md).*

Headless log-viewer core for [`structured_log`](../structured_log) — a bounded
in-memory buffer and a filterable controller for building a live, in-app log
viewer in Flutter. No Material, Cupertino, or any other design-system
dependency: this package renders nothing itself, so any UI skin can be built
on top of it — [`structured_log_material`](../structured_log_material),
[`structured_log_fluent`](../structured_log_fluent), and
[`structured_log_cupertino`](../structured_log_cupertino) all build on it.

> **Status:** published on [pub.dev](https://pub.dev/packages/structured_log_flutter)
> (`0.1.0`). `structured_log_material`, `structured_log_fluent`, and
> `structured_log_cupertino` all depend on it as a regular hosted
> dependency; within this monorepo, `melos bootstrap` resolves it to a
> path dependency instead.

## Features

- **`LogBuffer`** — a fixed-capacity ring buffer that plugs directly into
  `structured_log` as an `OutputFunction`/`LogSink.output`
- **Live updates** — `LogBuffer.entries` is a `ValueListenable`, so a widget
  can rebuild as entries arrive without polling — once per burst, not once
  per entry
- **`LogViewerController`** — a `ChangeNotifier` with level/category/search
  filtering, pause/resume, and clearing, all applied on top of a `LogBuffer`
- **`debugPrintOutput`** — a sink output for a phone's console: one plain
  line per entry through `debugPrint`, no ANSI colours
- **`logLevelColor(LogLevel level, Brightness brightness)`** — the
  canonical `LogLevel` indicator color, shared by every skin built on this
  package so the palette can't drift between them
- **Zero design-system dependency** — only `dart:ui`,
  `package:flutter/foundation.dart`, and `structured_log`

## Installation

```yaml
dependencies:
  structured_log_flutter: ^0.1.0
```

It needs `structured_log` 0.3.0 or later.

Within this monorepo, `melos bootstrap` resolves it to a path dependency
instead:

```yaml
dependencies:
  structured_log_flutter:
    path: ../structured_log_flutter
```

## Quick Start

```dart
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart';

final buffer = LogBuffer(capacity: 500);
final controller = LogViewerController(buffer);

StructlogConfiguration.configure(sinks: [
  LogSink(name: 'console', output: coloredConsoleOutput),
  LogSink(name: 'viewer', output: buffer.capture),
]);

getLogger().info('user_login', context: {'user_id': 42});

controller.levelFilter = LogLevel.warning; // only warning and above
controller.searchQuery = 'login';          // further narrowed by text
print(controller.visibleEntries);
```

## API Reference

### `LogBuffer`

| Member | Description |
|---|---|
| `LogBuffer({int capacity = 500})` | Creates an empty buffer; oldest entry evicted once `capacity` is exceeded |
| `capture(Map<String, dynamic> entry, LogLevel level)` | Matches `OutputFunction`'s signature — pass it directly as a sink's `output` |
| `entries` | `ValueListenable<List<Map<String, dynamic>>>`, oldest first |
| `clear()` | Empties the buffer and notifies `entries`' listeners at once |

`entries.value` is always current, but its listeners are told at most once
per turn of the event loop: a burst of entries logged in one go — a
request's worth, a tight loop — is one notification and one rebuild, not one
per entry. The list it returns is unmodifiable and never changes once read,
so it is safe to hold on to; reading it twice with no capture in between
gives the same list — it is copied once per change that is read, not once
per entry.

`LogBuffer` keeps entries in memory only. For logs that outlive the app,
use the file outputs, which come from `package:structured_log/io.dart`.

### `LogViewerController`

A `ChangeNotifier` wrapping a `LogBuffer`:

| Member | Description |
|---|---|
| `levelFilter` (`LogLevel?`) | Minimum level a visible entry must have; `null` = no restriction |
| `categoryFilter` (`String?`) | Exact `category` context value required; `null` = no restriction |
| `searchQuery` (`String`) | Case-insensitive substring match against `event` and every other context value (`level`/`timestamp` excluded) |
| `paused` (`bool`) | While `true`, `visibleEntries` stays frozen at the entries visible when paused, even as `buffer` keeps capturing |
| `visibleEntries` | The buffer's entries, filtered by the three properties above |
| `clear()` | Clears `buffer` (and any frozen snapshot) and notifies listeners |
| `dispose()` | Detaches from `buffer.entries` — call when the controller is no longer needed |

### `debugPrintOutput`

An `OutputFunction` that writes each entry as one line through
`debugPrint`, with no ANSI colours — the local time (from `timestamp`, to
the millisecond), the level, the `event`, and every other field as
`key=value` pairs:

```text
12:30:15.250 INFO login user="u" attempt=2
```

```dart
StructlogConfiguration.configure(sinks: [
  LogSink(name: 'console', output: debugPrintOutput),
]);
```

Use it where logs are read in logcat or the Xcode console. `defaultOutput`
pretty-prints JSON across several lines, which those consoles interleave
with everything else, and `coloredConsoleOutput`'s escape codes show up in
the iOS console as noise. Values are escaped the way `structured_log`'s
`formatLogfmt` escapes them, so a value holding a newline stays on its
line. `debugPrint` throttles a burst so Android does not drop lines, but it
does not shorten one — logcat cuts a line past about 4 KB. In a terminal on
a desktop, `coloredConsoleOutput` is still the more readable choice.

### `logLevelOf(Map<String, dynamic> entry)`

Parses an entry's `level` context key back into a `LogLevel`, matching by
name — returns `null` if missing or unrecognized. Exposed as a standalone
function so a UI skin (like `structured_log_material`) doesn't need to
reimplement this parsing.

### `logLevelColor(LogLevel level, Brightness brightness)`

The single source of truth for `LogLevel` indicator colors, used by every
skin's list row, detail view, and badges. Lives here (not in any one skin)
because `Color`/`Brightness` aren't tied to Material, Cupertino, or Fluent
— this table is genuinely design-system-neutral, unlike the widgets built
on top of it.

## Building a UI Skin

`structured_log_flutter` intentionally renders nothing — wire a
`LogViewerController` up to whatever widgets you like, listening to it as
any other `ChangeNotifier` (`AnimatedBuilder`, `ListenableBuilder`, etc.) and
reading `visibleEntries` for what to display. See
[`structured_log_material`](../structured_log_material),
[`structured_log_fluent`](../structured_log_fluent), and
[`structured_log_cupertino`](../structured_log_cupertino) for complete
reference implementations (list, expanded-entry detail, empty states) on
Material 3, Fluent UI, and Cupertino respectively.

## Related packages

The rest of the `structured_log` family:

**Core**

- [`structured_log`](https://pub.dev/packages/structured_log) — structured JSON logging with context binding, processors and multi-sink routing

**In-app log viewer**

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

## License

MIT
