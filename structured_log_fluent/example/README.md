# structured_log_fluent example

A runnable demo of [`structured_log_fluent`](../): wires `structured_log`
into `structured_log_flutter`'s `LogBuffer`/`LogViewerController`, and
embeds `FluentLogViewerPage`.

## Running (web)

From this directory:

```bash
flutter pub get
flutter run -d chrome
```

Tap "Log an info event" / "Log an error event" a few times, then "Open log
viewer" to see them live in the Fluent (WinUI-style) log viewer — try the
search box, the level dropdown, selecting a row to see its context in the
detail pane, and the pause/clear actions in the header.
