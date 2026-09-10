# structured_log_material

*Читать на [русском](README.ru.md).*

A ready-to-use Material 3 in-app log viewer for
[`structured_log`](../structured_log), built on
[`structured_log_flutter`](../structured_log_flutter)'s
`LogViewerController`: a live, newest-first list with search and level
filtering, a bottom-sheet detail view with full context and copy, and an
empty state that distinguishes "no logs yet" from "no logs match the
current filter".

> **Status:** not yet published to pub.dev (`0.1.0-dev.1`, `publish_to:
> none` — depends on the also-unpublished `structured_log_flutter` as a
> path dependency). Design reference: the
> [Log Viewer UI Concepts](https://claude.ai/code/artifact/400091b3-da51-4f73-a1fb-2ce779515de0)
> canvas (Material section — Cupertino/Fluent there are mockups only, not
> implemented).

## Features

- **`MaterialLogViewerPage`** — a full screen: top app bar (title, search,
  pause/resume, clear-all), level-filter chips, a live newest-first list
- **`LogEntryTile`** — one row: level-colored dot, `event`, formatted time,
  and a category tag if the entry has one
- **`LogEntryDetailSheet`** — tap a row to see its full context as
  formatted key/value pairs, with a "Copy context" action
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

## API Reference

| Widget | Description |
|---|---|
| `MaterialLogViewerPage({required LogViewerController controller})` | The full screen |
| `LogEntryTile({required entry, required onTap})` | One list row |
| `LogEntryDetailSheet({required entry})` | The expanded-entry bottom sheet content |
| `LogViewerEmptyState({required hasLogs, required onClearFilters})` | The two-variant empty state |
| `logLevelColor(LogLevel level, Brightness brightness)` | The canonical level-indicator color — the single place this palette is defined |

`entry` throughout is the `Map<String, dynamic>` shape `structured_log`
produces directly — no separate typed model.

## License

MIT
