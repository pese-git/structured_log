---
title: "Packages"
---

Eleven libraries you embed directly in your own Dart or Flutter app —
install one, import it, and go. (For the self-hosted server and its
admin client, see the [guides](/guides/) instead.)

| Package | What it is |
|---|---|
| [structured_log](/packages/structured_log/) | The core library — structured JSON logging with context binding, processors, and multi-sink output routing. Start here regardless of platform. |
| [structured_log_flutter](/packages/structured_log_flutter/) | A headless log-viewer core for Flutter: a bounded `LogBuffer` sink and a filterable `LogViewerController`. Build your own UI on top of it, or use one of the three skins below. |
| [structured_log_material](/packages/structured_log_material/) | A ready-to-use Material 3 in-app log viewer, built on `structured_log_flutter`. |
| [structured_log_fluent](/packages/structured_log_fluent/) | A ready-to-use Fluent UI (WinUI-style) in-app log viewer, built on `structured_log_flutter`. |
| [structured_log_cupertino](/packages/structured_log_cupertino/) | A ready-to-use Cupertino (iOS-style) in-app log viewer, built on `structured_log_flutter`. |
| [structured_log_remote_sync](/packages/structured_log_remote_sync/) | A `RemoteSyncLogOutput` sink that ships log entries to a `structured_log_server` instance over HTTP — batching, retry with backoff, a bounded buffer. See the [Developer Guide](/guides/developer-guide/) for the full ingestion walkthrough. |
| [structured_log_bloc](/packages/structured_log_bloc/) | A `BlocObserver` that logs every bloc's and cubit's lifecycle, events, state changes and errors as `structured_log` entries. Works with `flutter_bloc` as is. |
| [structured_log_dio](/packages/structured_log_dio/) | A `dio` interceptor that logs every request and its outcome, with the level following the status code and auth headers, cookies and token-like query parameters redacted. |
| [structured_log_http_client](/packages/structured_log_http_client/) | The same for `package:http`: a client that wraps any `http.Client` and logs every call it passes through. |
| [structured_log_go_router](/packages/structured_log_go_router/) | Logs every `go_router` navigation — location, route pattern, previous location — plus redirects and routing errors, with token-like query parameters redacted. |
| [structured_log_cherrypick](/packages/structured_log_cherrypick/) | A `CherryPickObserver` that logs what the `cherrypick` DI container does — scopes, modules, cycles, resolve errors — without ever printing an instance. |
| [structured_log_drift](/packages/structured_log_drift/) | A drift `QueryInterceptor` that writes every query — SQL, duration, rows — plus batches, failures and transaction ends, flags slow queries and keeps argument values out by default. |
| [structured_log_logging](/packages/structured_log_logging/) | A bridge that writes every `package:logging` record as a `structured_log` entry — message, logger, level by value, error and stack trace — so the logs of libraries that write through `package:logging` reach the same sinks as your own. |

Looking for `structured_log_http`? It was renamed to
`structured_log_remote_sync` (`HttpLogOutput` → `RemoteSyncLogOutput`) and is
discontinued; [its page](/packages/structured_log_http/) explains the move.

Each package's page below is its README verbatim: installation, a quick
start, the full feature list, and an API reference table.
