# structured_log_flutter

[![CI](https://github.com/pese-git/structured_log/actions/workflows/ci.yml/badge.svg)](https://github.com/pese-git/structured_log/actions/workflows/ci.yml)

*Читать на [русском](README.ru.md).*

**The engine behind an in-app log viewer for Flutter: your app's recent
[`structured_log`](https://pub.dev/packages/structured_log) entries kept in
memory, filtered and ready for any UI — plus a clean one-line console output
for phones.**

## Why

A tester hits a bug on a device, and the logs that would explain it went to
a console nobody had attached — or scrolled away in logcat among the
system's own noise. The fix is to keep recent entries inside the app and
show them on demand. Whatever such a screen looks like, the parts under it
are the same: a buffer that doesn't grow without bound, filters by level,
category and text, and a pause that stops the list from moving while you
read it.

`structured_log_flutter` is exactly those parts, without a single widget. It
renders nothing and depends on no design system, so the three ready-made
viewers — Material, Fluent and Cupertino — share it, and you can build your
own on it. Most apps never touch it directly: they pick a skin. Use this
package when you want a viewer in your own design system, or want the
recent entries in code — say, to attach them to a bug report. And for the
times the console *is* within reach, it adds `debugPrintOutput`, which
writes each entry as one readable line instead of multi-line JSON.

## Features

### Collecting entries

- **One more sink** — `LogBuffer.capture` has the `OutputFunction`
  signature, so the buffer is a `LogSink` next to your console; no logging
  call changes.
- **Bounded memory** — a ring buffer of fixed capacity (500 by default):
  the oldest entry is evicted first, and nothing is written to disk.
- **One rebuild per burst** — `entries` is a `ValueListenable` whose value
  is always current, but whose listeners hear about a burst of entries
  once, not once per entry: a request that logs fifty lines costs the UI a
  single rebuild.
- **Snapshots you can keep** — the list you read is unmodifiable and never
  changes afterwards, so it is safe to hold on to or diff against a later
  read.

### Driving a viewer

- **Filters** — `LogViewerController` narrows entries by minimum level,
  exact category, and case-insensitive text search over the event and every
  context value.
- **Pause** — freezes the visible list while the buffer keeps capturing, so
  entries don't scroll away mid-read; resume to catch up.
- **Clear** — empties the buffer and any paused snapshot in one call.
- **A plain `ChangeNotifier`** — works with `AnimatedBuilder`,
  `ListenableBuilder` or whatever state management you already use.

### Reading logs on a console

- **`debugPrintOutput`** — one line per entry
  (`12:30:15.250 INFO login user="u" attempt=2`): local time, no ANSI
  codes, values escaped so a newline can't break the line. It goes through
  `debugPrint`, which throttles bursts so Android doesn't drop lines.

### Shared by every skin

- **One level palette** — `logLevelColor()` gives each `LogLevel` a light
  and a dark color, so the Material, Fluent and Cupertino viewers can't
  drift apart; `logLevelOf()` reads an entry's level back.
- **No design system** — depends only on `dart:ui`,
  `package:flutter/foundation.dart` and `structured_log`.

## Where it fits

[`structured_log`](https://pub.dev/packages/structured_log) writes entries
and routes them to sinks; this package is the sink that keeps them inside
the app, plus the state a viewer needs to show them.
[`structured_log_material`](https://pub.dev/packages/structured_log_material),
[`structured_log_fluent`](https://pub.dev/packages/structured_log_fluent) and
[`structured_log_cupertino`](https://pub.dev/packages/structured_log_cupertino)
are ready-made screens built on it. All of this runs entirely in your app,
with no server; if you later ship logs to a self-hosted server with
[`structured_log_remote_sync`](https://pub.dev/packages/structured_log_remote_sync),
the viewer keeps working alongside it, since every sink is independent.
More in the documentation at
[structured-log.openidealab.com](https://structured-log.openidealab.com) and
in the [Embedding Guide](https://structured-log.openidealab.com/guides/embedding-guide/).

## Installation

```yaml
dependencies:
  structured_log: ^0.3.0
  structured_log_flutter: ^0.1.2
```

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
| `capacity` | The maximum number of entries held at once |
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
| `visibleEntries` | The buffer's entries, filtered by the three properties above, oldest first |
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
reading `visibleEntries` for what to display. A bare-bones list, using
nothing but `package:flutter/widgets.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart';

class PlainLogList extends StatelessWidget {
  const PlainLogList({required this.controller, super.key});

  final LogViewerController controller;

  @override
  Widget build(BuildContext context) {
    final brightness = MediaQuery.platformBrightnessOf(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        // visibleEntries is oldest first; show the newest on top.
        final entries = controller.visibleEntries.reversed.toList();
        return ListView.builder(
          itemCount: entries.length,
          itemBuilder: (context, index) {
            final entry = entries[index];
            final level = logLevelOf(entry);
            return Text(
              '${level?.name ?? '?'}  ${entry['event']}',
              style: TextStyle(
                color: level == null ? null : logLevelColor(level, brightness),
              ),
            );
          },
        );
      },
    );
  }
}
```

See
[`structured_log_material`](https://pub.dev/packages/structured_log_material),
[`structured_log_fluent`](https://pub.dev/packages/structured_log_fluent), and
[`structured_log_cupertino`](https://pub.dev/packages/structured_log_cupertino)
for complete reference implementations (list, expanded-entry detail, empty
states) on Material 3, Fluent UI, and Cupertino respectively.

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
