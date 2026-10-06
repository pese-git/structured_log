# structured_log_material

[![CI](https://github.com/pese-git/structured_log/actions/workflows/ci.yml/badge.svg)](https://github.com/pese-git/structured_log/actions/workflows/ci.yml)

*Читать на [русском](README.ru.md).*

**A ready-made Material 3 log viewer for your Flutter app: open a screen — or
dock a panel — and see what the app just logged, with search, filters and
every entry's full context.**

## Why

Something goes wrong while you're testing on a phone, and the explanation
is in logs printed to a console you can't see from there. This package puts
those logs on a screen inside the app: every
[`structured_log`](https://pub.dev/packages/structured_log) entry, newest
first, searchable and filterable by level and category, with a tap to see
an entry's full context and copy it into a bug report. Wiring it up is one
extra sink and one widget.

Pick it for apps built with Material (`MaterialApp`) — Android-first or
cross-platform. For a Windows-style desktop app built on `fluent_ui`, take
[`structured_log_fluent`](https://pub.dev/packages/structured_log_fluent);
for an app with an iOS look,
[`structured_log_cupertino`](https://pub.dev/packages/structured_log_cupertino).
If none of the three matches your design system, build your own on
[`structured_log_flutter`](https://pub.dev/packages/structured_log_flutter) —
the skins share it, so filtering and pausing behave the same everywhere.

## Features

### Drop-in

- **A screen or a panel** — `MaterialLogViewerPage` is a complete screen
  with an app bar (and a back button when pushed); `MaterialLogViewer` is
  the same viewer with no page chrome, for a tab, a side panel or a dialog.
- **Adapts to the space it gets** — it measures its own width, not the
  window's: below 700 logical pixels a tap opens the entry in a modal bottom
  sheet; from 700 up, the list and a detail panel sit side by side, with the
  newest entry selected.

### Finding the entry

- **A live list, newest first** — new entries appear as the app logs them.
- **Search** — across event names and every context value.
- **Level filter** — chips for All, Debug+, Info+, Warning+ and Error+.
- **Category filter** — chips built from the categories actually in the
  buffer, hidden while there are fewer than two; entries from adapters such
  as [`structured_log_dio`](https://pub.dev/packages/structured_log_dio)
  (`http`) or [`structured_log_bloc`](https://pub.dev/packages/structured_log_bloc)
  (`bloc`) become a filter on their own.
- **Pause and clear** — freeze the list while you read; clear it to start a
  fresh reproduction.

### Reading it

- **Full context** — level, time and event on top, then every other field
  as a key/value pair.
- **Copy context** — one tap puts the fields on the clipboard as
  `key: value` lines.
- **Clear empty states** — "No logs yet" when nothing was captured, "No
  logs match the current filter" with a "Clear filters" action when the
  filters hid everything.

### Looks like your app

- **Follows your theme** — colors and typography come from
  `Theme.of(context)`, light and dark; only the level colors are fixed, and
  they are the same in every skin.
- **Parts to compose your own layout** — `LogEntryTile`,
  `LogCategoryChips`, `LogEntryDetailSheet`, `LogEntryDetailPanel` and
  `LogViewerEmptyState` are public.

## Where it fits

[`structured_log`](https://pub.dev/packages/structured_log) writes the
entries;
[`structured_log_flutter`](https://pub.dev/packages/structured_log_flutter)
keeps the recent ones in memory and handles filtering and pausing; this
package is the Material face on top, a sibling of
[`structured_log_fluent`](https://pub.dev/packages/structured_log_fluent) and
[`structured_log_cupertino`](https://pub.dev/packages/structured_log_cupertino).
It works entirely inside your app, with no server; if you also ship logs to
a self-hosted server with
[`structured_log_remote_sync`](https://pub.dev/packages/structured_log_remote_sync),
the viewer keeps showing them locally. More in the documentation at
[structured-log.openidealab.com](https://structured-log.openidealab.com) and
in the [Embedding Guide](https://structured-log.openidealab.com/guides/embedding-guide/).
Design reference: the
[Log Viewer UI Concepts](https://claude.ai/code/artifact/400091b3-da51-4f73-a1fb-2ce779515de0)
canvas (Material section).

## Installation

```yaml
dependencies:
  structured_log: ^0.3.0
  structured_log_flutter: ^0.1.2
  structured_log_material: ^0.1.1
```

Within this monorepo, `melos bootstrap` resolves both internal packages to
path dependencies instead:

```yaml
dependencies:
  structured_log_flutter:
    path: ../structured_log_flutter
  structured_log_material:
    path: ../structured_log_material
```

## Quick Start

```dart
import 'package:flutter/material.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart';
import 'package:structured_log_material/structured_log_material.dart';

void main() {
  final buffer = LogBuffer();
  final controller = LogViewerController(buffer);

  StructlogConfiguration.configure(sinks: [
    LogSink(name: 'viewer', output: buffer.capture),
  ]);

  runApp(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: OutlinedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => MaterialLogViewerPage(controller: controller),
              ),
            ),
            child: const Text('Open log viewer'),
          ),
        ),
      ),
    ),
  ));
}
```

See [`example/`](https://github.com/pese-git/structured_log/tree/master/emb/structured_log_material/example) for a full runnable app (including web) — run it
with `flutter run -d chrome` from that directory.

To embed the viewer inside existing page chrome instead of giving it the
whole screen, use `MaterialLogViewer` directly:

```dart
Row(
  children: [
    Expanded(child: MyAppContent()),
    SizedBox(
      width: 420,
      child: MaterialLogViewer(controller: controller),
    ),
  ],
)
```

## Screenshots

`MaterialLogViewerPage` as the full screen — master-detail split at this
width, list on the left and the selected entry's full context on the
right:

![MaterialLogViewerPage: a live list of log entries on the left, filter chips and level filters above it, and the selected entry's full context with a copy action on the right](doc/screenshots/full-screen.png)

`MaterialLogViewer` embedded in a side panel next to other app content —
the same widget, no page chrome of its own:

![MaterialLogViewer docked as a 2:1-flex side panel next to placeholder app content, showing the same log list and detail view](doc/screenshots/embedded.png)

On a phone-width screen, the same page collapses to a list, and tapping
an entry opens `LogEntryDetailSheet` as a modal bottom sheet instead of
a side panel:

![MaterialLogViewerPage on a narrow, phone-width screen: the log list with a bottom sheet open on top, dimming the list behind it, showing the tapped entry's full context and a copy action](doc/screenshots/mobile.png)

## API Reference

| Widget | Description |
|---|---|
| `MaterialLogViewer({required LogViewerController controller})` | The log viewer as an embeddable widget (no page chrome) |
| `MaterialLogViewerPage({required LogViewerController controller})` | The full screen |
| `LogCategoryChips({required LogViewerController controller, String allLabel = 'All'})` | The category-filter chip row |
| `LogEntryTile({required entry, required onTap, bool selected = false})` | One list row |
| `LogEntryDetailSheet({required entry})` | The expanded-entry bottom sheet content (narrow screens) |
| `LogEntryDetailPanel({required entry})` | The expanded-entry non-modal panel content (wide screens) |
| `LogViewerEmptyState({required hasLogs, required onClearFilters})` | The two-variant empty state |
| `logLevelColor(LogLevel level, Brightness brightness)` | The canonical level-indicator color — defined once in `structured_log_flutter`, shared by every skin |

`entry` throughout is the `Map<String, dynamic>` shape `structured_log`
produces directly — no separate typed model.

## Related packages

The rest of the `structured_log` family:

**Core**

- [`structured_log`](https://pub.dev/packages/structured_log) — structured JSON logging with context binding, processors and multi-sink routing

**In-app log viewer**

- [`structured_log_flutter`](https://pub.dev/packages/structured_log_flutter) — headless viewer core: `LogBuffer` and `LogViewerController`
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

MIT
