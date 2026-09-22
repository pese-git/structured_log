---
title: "Packages"
---

Six libraries you embed directly in your own Dart or Flutter app —
install one, import it, and go. (For the self-hosted server and its
admin client, see the [guides](/guides/) instead.)

| Package | What it is |
|---|---|
| [structured_log](/packages/structured_log/) | The core library — structured JSON logging with context binding, processors, and multi-sink output routing. Start here regardless of platform. |
| [structured_log_flutter](/packages/structured_log_flutter/) | A headless log-viewer core for Flutter: a bounded `LogBuffer` sink and a filterable `LogViewerController`. Build your own UI on top of it, or use one of the three skins below. |
| [structured_log_material](/packages/structured_log_material/) | A ready-to-use Material 3 in-app log viewer, built on `structured_log_flutter`. |
| [structured_log_fluent](/packages/structured_log_fluent/) | A ready-to-use Fluent UI (WinUI-style) in-app log viewer, built on `structured_log_flutter`. |
| [structured_log_cupertino](/packages/structured_log_cupertino/) | A ready-to-use Cupertino (iOS-style) in-app log viewer, built on `structured_log_flutter`. |
| [structured_log_http](/packages/structured_log_http/) | An `HttpLogOutput` sink that ships log entries to a `structured_log_server` instance over HTTP — batching, retry with backoff, a bounded buffer. See the [Developer Guide](/guides/developer-guide/) for the full ingestion walkthrough. |

Each package's page below is its README verbatim: installation, a quick
start, the full feature list, and an API reference table.
