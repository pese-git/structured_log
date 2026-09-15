# structured_log_cupertino

*Читать на [русском](README.ru.md).*

A ready-to-use Cupertino (iOS-style) in-app log viewer for
[`structured_log`](../structured_log), built on
[`structured_log_flutter`](../structured_log_flutter)'s
`LogViewerController`: a live, newest-first list with search, category, and
level filtering, an entry-detail view with full context and copy, and an
empty state that distinguishes "no logs yet" from "no logs match the
current filter". Available both as a full screen
(`CupertinoLogViewerPage`) and as a plain embeddable widget
(`CupertinoLogViewer`) for dropping into existing page chrome — a tab, a
side panel, ...

How the selected entry's detail is shown is adaptive, matching iOS
conventions at each size rather than picking one pattern for every screen:
below a width breakpoint (the mobile-style default) tapping a row **pushes**
a new screen via `CupertinoPageRoute` — the standard iOS "drill into
detail" pattern (Mail, Settings on iPhone); at or above it, the list and a
non-modal detail panel show side by side instead, matching how those same
apps behave on iPad.

> **Status:** not yet published to pub.dev (`0.1.0-dev.1`), but no longer
> blocked from it — `publish_to: none` has been dropped now that the
> package is validated (`dart pub publish --dry-run` passes; `CHANGELOG.md`
> will appear once `melos version` runs, see [AGENTS.md](../AGENTS.md)).
> Design/decision history:
> [openspec/changes/add-structured-log-cupertino/](../openspec/changes/add-structured-log-cupertino/).

## Features

- **`CupertinoLogViewer`** — the log viewer as a plain embeddable widget: a
  toolbar (`CupertinoSearchTextField`, pause/resume, clear-all) above a
  category-filter pill row and a level-filter
  `CupertinoSlidingSegmentedControl`, above a live newest-first list — no
  page chrome of its own, so it can be dropped anywhere in an existing
  layout
- **`CupertinoLogViewerPage`** — a thin `CupertinoPageScaffold` wrapper
  around `CupertinoLogViewer` for the full-screen case: adds a navigation
  bar titled "Logs" and, when pushed via `Navigator`, a back button
  (`CupertinoNavigationBar`'s own)
- **Adaptive** — narrow screens: list + a pushed `LogEntryDetailPanel`
  screen per tap (the iPhone pattern); wide screens: list and a non-modal
  `LogEntryDetailPanel` side by side (the iPad pattern) — reacts to the
  width *this widget* is actually given, not the window's
- **`LogCategoryFilterBar`** — a horizontally scrollable row of
  pill-shaped filter buttons for `category`, derived from the distinct
  values currently in the buffer; hidden automatically when fewer than two
  are present (a `CupertinoSlidingSegmentedControl` doesn't fit a dynamic,
  open-ended option set — that's used for the level filter instead, which
  has a small, fixed one)
- **`LogEntryTile`** — one row: a colored dot for the level, `event`,
  formatted time, and a category tag if the entry has one; a trailing
  chevron on narrow screens (drills into a pushed detail screen), tinted
  instead when it's the entry shown in an adjacent panel on wide screens
- **`LogEntryDetailPanel`** — the selected entry's full context as
  formatted key/value pairs, with a "Copy" action — a plain, non-modal
  widget (no drag handle, no "Close" button) reused both pushed as its own
  screen and shown inline in the master-detail split
- **`LogViewerEmptyState`** — "No logs yet" vs. "No logs match the current
  filter" (with a "Clear filters" action)
- **Theme-aware** — colors and typography come from `CupertinoTheme.of` /
  `CupertinoColors` (light/dark both supported via `resolveFrom`); only the
  level-indicator palette is fixed (`logLevelColor`, shared with every
  skin via `structured_log_flutter`)

## Installation

Within this monorepo:

```yaml
dependencies:
  structured_log_flutter:
    path: ../structured_log_flutter
  structured_log_cupertino:
    path: ../structured_log_cupertino
```

## Quick Start

```dart
import 'package:flutter/cupertino.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart';
import 'package:structured_log_cupertino/structured_log_cupertino.dart';

void main() {
  final buffer = LogBuffer();
  final controller = LogViewerController(buffer);

  StructlogConfiguration.configure(sinks: [
    LogSink(name: 'viewer', output: buffer.capture),
  ]);

  runApp(CupertinoApp(
    home: CupertinoLogViewerPage(controller: controller),
  ));
}
```

See [`example/`](example/) for a full runnable app (including web) — run it
with `flutter run -d chrome` from that directory.

To embed the viewer inside existing page chrome instead of giving it the
whole screen, use `CupertinoLogViewer` directly:

```dart
Row(
  children: [
    Expanded(child: MyAppContent()),
    SizedBox(
      width: 420,
      child: CupertinoLogViewer(controller: controller),
    ),
  ],
)
```

## API Reference

| Widget | Description |
|---|---|
| `CupertinoLogViewer({required LogViewerController controller})` | The log viewer as an embeddable widget (no page chrome) |
| `CupertinoLogViewerPage({required LogViewerController controller})` | The full screen |
| `LogCategoryFilterBar({required LogViewerController controller, String allLabel = 'All'})` | The category-filter pill row |
| `LogEntryTile({required entry, required onTap, bool selected = false, bool showsDisclosureIndicator = true})` | One list row |
| `LogEntryDetailPanel({required entry})` | The full-context detail content (pushed or side-by-side) |
| `LogViewerEmptyState({required hasLogs, required onClearFilters})` | The two-variant empty state |
| `logLevelColor(LogLevel level, Brightness brightness)` | The canonical level-indicator color — defined once in `structured_log_flutter`, shared by every skin |

`entry` throughout is the `Map<String, dynamic>` shape `structured_log`
produces directly — no separate typed model.

## License

MIT
