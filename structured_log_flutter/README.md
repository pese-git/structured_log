# structured_log_flutter

*Читать на [русском](README.ru.md).*

Headless log-viewer core for [`structured_log`](../structured_log) — a bounded
in-memory buffer and a filterable controller for building a live, in-app log
viewer in Flutter. No Material, Cupertino, or any other design-system
dependency: this package renders nothing itself, so any UI skin can be built
on top of it. [`structured_log_material`](../structured_log_material) is the
first such skin.

> **Status:** not yet published to pub.dev (`0.1.0-dev.1`). Depend on it as a
> path dependency within this monorepo for now.

## Features

- **`LogBuffer`** — a fixed-capacity ring buffer that plugs directly into
  `structured_log` as an `OutputFunction`/`LogSink.output`
- **Live updates** — `LogBuffer.entries` is a `ValueListenable`, so a widget
  can rebuild on every new entry without polling
- **`LogViewerController`** — a `ChangeNotifier` with level/category/search
  filtering, pause/resume, and clearing, all applied on top of a `LogBuffer`
- **Zero design-system dependency** — only `package:flutter/foundation.dart`
  and `structured_log`

## Installation

Within this monorepo:

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
| `clear()` | Empties the buffer and notifies `entries`' listeners |

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

### `logLevelOf(Map<String, dynamic> entry)`

Parses an entry's `level` context key back into a `LogLevel`, matching by
name — returns `null` if missing or unrecognized. Exposed as a standalone
function so a UI skin (like `structured_log_material`) doesn't need to
reimplement this parsing.

## Building a UI Skin

`structured_log_flutter` intentionally renders nothing — wire a
`LogViewerController` up to whatever widgets you like, listening to it as
any other `ChangeNotifier` (`AnimatedBuilder`, `ListenableBuilder`, etc.) and
reading `visibleEntries` for what to display. See
[`structured_log_material`](../structured_log_material) for a complete
reference implementation (list, expanded-entry detail, empty states) on
Material 3.

## License

MIT
