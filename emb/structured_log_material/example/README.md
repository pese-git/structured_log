# structured_log_material example

A runnable demo of [`structured_log_material`](../): wires `structured_log`
into `structured_log_flutter`'s `LogBuffer`/`LogViewerController`, and
embeds `MaterialLogViewerPage`.

## Running (web)

From this directory:

```bash
flutter pub get
flutter run -d chrome
```

Tap "Log an info event" / "Log an error event" a few times, then "Open log
viewer" to see them live in the Material 3 log viewer — try the search
field, the level filter chips, tapping a row for its full context, and the
pause/clear actions in the top bar.
