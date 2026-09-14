[![CI](https://github.com/pese-git/structured_log/actions/workflows/ci.yml/badge.svg)](https://github.com/pese-git/structured_log/actions/workflows/ci.yml)

*Читать на [русском](README.ru.md).*

# structured_log Workspace

A Melos + FVM monorepo for structured logging in Dart, inspired by
[Python's structlog](https://www.structlog.org/), plus an in-app log
viewer ecosystem for Flutter built on top of it.

## Packages

- **[`structured_log`](emb/structured_log/)** — the core library: structured
  JSON logging with context binding, typed correlation fields, processors,
  and multi-sink output routing. Zero runtime dependencies beyond `meta`.
  Published on [pub.dev](https://pub.dev/packages/structured_log).

- **[`structured_log_flutter`](emb/structured_log_flutter/)** — a headless
  log-viewer core for Flutter apps: a bounded `LogBuffer` that plugs
  directly into `structured_log` as a sink, and a filterable
  `LogViewerController`. No dependency on any specific design system —
  the foundation any UI skin builds on. *Not yet published.*

- **[`structured_log_material`](emb/structured_log_material/)** — a
  ready-to-use Material 3 in-app log viewer built on
  `structured_log_flutter`: live list, search and level filtering,
  expanded-entry detail with copy, and empty states. Includes a runnable
  example app (`emb/structured_log_material/example/`, web-capable). *Not yet
  published.*

- **[`structured_log_fluent`](emb/structured_log_fluent/)** — a ready-to-use
  Fluent UI (WinUI-style) in-app log viewer built on
  `structured_log_flutter`: master-detail split view, search and level
  filtering, a detail pane with copy, and empty states. Includes a
  runnable example app (`emb/structured_log_fluent/example/`, web-capable).
  *Not yet published.*

- **[`structured_log_cupertino`](emb/structured_log_cupertino/)** — a
  ready-to-use Cupertino (iOS-style) in-app log viewer built on
  `structured_log_flutter`: search, category and level filtering, a
  pushed detail screen on narrow screens (list + master-detail split on
  wide/iPad-size ones instead), and empty states. Includes a runnable
  example app (`emb/structured_log_cupertino/example/`, web-capable). *Not yet
  published.*

- **[`structured_log_http`](emb/structured_log_http/)** — an `HttpLogOutput`
  sink that ships log entries to a `structured_log_server` instance over
  HTTP, with batching and retry/backoff. Only dependency is `structured_log`
  itself. *Scaffolding stage — implementation in progress.*

- **[`structured_log_server`](backend/structured_log_server/)** — a
  self-hosted, multi-tenant server for log ingestion, storage, query and
  live streaming (`shelf`/`shelf_router` + `drift`/SQLite). *Scaffolding
  stage — implementation in progress.*

## Repository Layout

Packages are grouped by top-level category, each listed by its full path
in [melos.yaml](melos.yaml): `emb/` for libraries meant to be embedded in
another app (`structured_log` and its log-viewer skins, `structured_log_http`),
`backend/` for standalone server apps (`structured_log_server`), `frontend/`
for standalone client apps with a UI (currently empty — `structured_log_admin_client`
lands here as it's built), and `packages/` reserved for anything that doesn't
fit the three categories above (currently empty). See [AGENTS.md](AGENTS.md)
for the full toolchain reference (commands, conventions, versioning, CI) if
you're contributing.

Design and planning history for the Flutter log-viewer packages lives in
[openspec/changes/add-structured-log-flutter/](openspec/changes/add-structured-log-flutter/),
[openspec/changes/add-structured-log-fluent/](openspec/changes/add-structured-log-fluent/),
and
[openspec/changes/add-structured-log-cupertino/](openspec/changes/add-structured-log-cupertino/);
for the server, its HTTP sender, and the admin client, see
[openspec/changes/add-structured-log-server/](openspec/changes/add-structured-log-server/)
(why, technical decisions, requirements, task-by-task progress, including the
staged Stage 0/Stage 1/... delivery plan).

## Quick Start

```dart
import 'package:structured_log/structured_log.dart';

void main() {
  final log = getLogger();
  log.info('user_login', context: {'user_id': 42, 'ip': '127.0.0.1'});
}
```

See each package's own README for installation and full API reference.

## License

MIT — see [LICENSE](LICENSE).
