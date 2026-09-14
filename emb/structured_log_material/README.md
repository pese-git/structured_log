# structured_log_material

*Читать на [русском](README.ru.md).*

A ready-to-use Material 3 in-app log viewer for
[`structured_log`](../structured_log), built on
[`structured_log_flutter`](../structured_log_flutter)'s
`LogViewerController`: a live, newest-first list with search, category, and
level filtering, a bottom-sheet detail view with full context and copy, and
an empty state that distinguishes "no logs yet" from "no logs match the
current filter". Available both as a full screen (`MaterialLogViewerPage`)
and as a plain embeddable widget (`MaterialLogViewer`) for dropping into
existing page chrome — a tab, a side panel, a dialog, ...

> **Status:** not yet published to pub.dev (`0.1.0-dev.1`, `publish_to:
> none` — depends on the also-unpublished `structured_log_flutter` as a
> path dependency). Design reference: the
> [Log Viewer UI Concepts](https://claude.ai/code/artifact/400091b3-da51-4f73-a1fb-2ce779515de0)
> canvas (Material section — [`structured_log_fluent`](../structured_log_fluent)
> and [`structured_log_cupertino`](../structured_log_cupertino) are
> implemented too now, from the Fluent/Cupertino sections of the same
> canvas).

## Features

- **`MaterialLogViewer`** — the log viewer as a plain embeddable widget: a
  toolbar (search field, pause/resume, clear-all) above category- and
  level-filter chips and a live newest-first list — no page chrome of its
  own, so it can be dropped anywhere in an existing layout
- **`MaterialLogViewerPage`** — a thin `Scaffold`/`AppBar` wrapper around
  `MaterialLogViewer` for the full-screen case: adds a title ("Logs") and,
  when pushed via `Navigator`, a back button (`AppBar`'s own)
- **Adaptive** — how the selected entry's context is shown reacts to the
  width *this widget* is actually given (its own constraints, not the
  window's): below the master-detail breakpoint (the mobile-style default)
  tapping a row opens `LogEntryDetailSheet` as a modal bottom sheet; at or
  above it, the list and a non-modal `LogEntryDetailPanel` show side by
  side instead — Material's own list-detail layout guidance for tablet and
  desktop
- **`LogCategoryChips`** — a `category`-filter chip row whose options are
  derived from the distinct `category` values currently in the buffer;
  hidden automatically when fewer than two are present
- **`LogEntryTile`** — one row: level-colored dot, `event`, formatted time,
  and a category tag if the entry has one; tinted when it's the entry shown
  in an adjacent `LogEntryDetailPanel`
- **`LogEntryDetailSheet`** — tap a row (on narrow screens) to see its full
  context as formatted key/value pairs in a modal bottom sheet, with a
  "Copy context" action
- **`LogEntryDetailPanel`** — the same context/copy content as
  `LogEntryDetailSheet`, but as a non-modal panel for the wide-screen
  master-detail split — no drag handle or "Close" button
- **`LogViewerEmptyState`** — "No logs yet" (nothing captured at all) vs.
  "No logs match the current filter" (with a "Clear filters" action)
- **Theme-aware** — colors and typography come from `Theme.of(context)`
  (light/dark both supported); only the level-indicator palette is fixed
  (`logLevelColor`), kept in one place so it can't drift between widgets

## Installation

Within this monorepo:

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

See [`example/`](example/) for a full runnable app (including web) — run it
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

## License

MIT
