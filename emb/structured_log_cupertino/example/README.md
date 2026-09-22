# structured_log_cupertino example

A runnable demo of [`structured_log_cupertino`](../): wires `structured_log`
into `structured_log_flutter`'s `LogBuffer`/`LogViewerController`, and
demonstrates both `CupertinoLogViewerPage` (full screen) and the embedded
`CupertinoLogViewer` docked in a side panel.

## Running (web)

From this directory:

```bash
flutter pub get
flutter run -d chrome
```

Tap "Log an info event" / "Log an error event" / "Log a protocol event" a
few times, then either "Open log viewer (full screen)" or "Open embedded
log viewer demo" to see them live in the Cupertino (iOS-style) log
viewer — try the search field, the category filter bar, the level
segmented control, tapping a row for its full context (pushed as its own
screen on narrow widths, shown side by side on wide/iPad-size ones), and
the pause/clear actions in the toolbar.
