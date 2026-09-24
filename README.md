[![CI](https://github.com/pese-git/structured_log/actions/workflows/ci.yml/badge.svg)](https://github.com/pese-git/structured_log/actions/workflows/ci.yml)

*Читать на [русском](README.ru.md).*

# structured_log Workspace

A Melos + FVM monorepo for structured logging in Dart, inspired by
[Python's structlog](https://www.structlog.org/) — the core library, an
in-app log viewer ecosystem for Flutter built on top of it, and a
self-hosted server for shipping logs off the device and reading them back.

## Packages

- **[`structured_log`](emb/structured_log/)** — the core library: structured
  JSON logging with context binding, typed correlation fields, processors,
  and multi-sink output routing. Zero runtime dependencies beyond `meta`.
  Published on [pub.dev](https://pub.dev/packages/structured_log).

- **[`structured_log_flutter`](emb/structured_log_flutter/)** — a headless
  log-viewer core for Flutter apps: a bounded `LogBuffer` that plugs
  directly into `structured_log` as a sink, and a filterable
  `LogViewerController`. No dependency on any specific design system —
  the foundation any UI skin builds on. Published on
  [pub.dev](https://pub.dev/packages/structured_log_flutter).

- **[`structured_log_material`](emb/structured_log_material/)** — a
  ready-to-use Material 3 in-app log viewer built on
  `structured_log_flutter`: live list, search and level filtering,
  expanded-entry detail with copy, and empty states. Includes a runnable
  example app (`emb/structured_log_material/example/`, web-capable).
  Published on [pub.dev](https://pub.dev/packages/structured_log_material).

- **[`structured_log_fluent`](emb/structured_log_fluent/)** — a ready-to-use
  Fluent UI (WinUI-style) in-app log viewer built on
  `structured_log_flutter`: master-detail split view, search and level
  filtering, a detail pane with copy, and empty states. Includes a
  runnable example app (`emb/structured_log_fluent/example/`, web-capable).
  Published on [pub.dev](https://pub.dev/packages/structured_log_fluent).

- **[`structured_log_cupertino`](emb/structured_log_cupertino/)** — a
  ready-to-use Cupertino (iOS-style) in-app log viewer built on
  `structured_log_flutter`: search, category and level filtering, a
  pushed detail screen on narrow screens (list + master-detail split on
  wide/iPad-size ones instead), and empty states. Includes a runnable
  example app (`emb/structured_log_cupertino/example/`, web-capable).
  Published on [pub.dev](https://pub.dev/packages/structured_log_cupertino).

- **[`structured_log_http`](emb/structured_log_http/)** — an `HttpLogOutput`
  sink that ships log entries to a `structured_log_server` instance over
  HTTP: batching by size or timeout, retry with backoff, a bounded buffer,
  and `flushed` to await delivery before exit. Never blocks the code that
  logged. Only dependency is `structured_log` itself. *Not yet published.*

- **[`structured_log_server`](backend/structured_log_server/)** — a
  self-hosted, multi-tenant server for log ingestion, storage, query and
  live streaming (`shelf`/`shelf_router` + `drift`, SQLite by default or
  PostgreSQL as an operator-chosen alternative). Ingestion, querying, SSE
  live streaming, groups/projects/secret keys/teams, authentication,
  RBAC, quotas, retention, rate limiting, user management, and the audit
  log all work today; self-service registration, password recovery, and
  email verification are specified but not built yet. Not published — it
  is a service you run, not a library you depend on.

- **[`structured_log_admin_ui`](frontend/structured_log_admin_ui/)** — the
  Flutter UI component library the admin client is built from (Atomic
  Design: tokens/atoms/molecules/organisms, Fluent UI–based). Depends
  only on `flutter` and `fluent_ui` — no knowledge of the client's data
  layer or navigation. Includes a runnable component gallery
  (`frontend/structured_log_admin_ui/example/`, web-capable). Not
  published — styled specifically for this client, not a general-purpose kit.

- **[`structured_log_admin_client`](frontend/structured_log_admin_client/)**
  — the web app operators and their teams actually use: sign-in and
  forced password change, a role-scoped admin dashboard, groups/
  projects/teams/secret keys, log search with live tailing, user
  management, and the audit log. Localized (English/Russian). Not
  published — a standalone application, not a library.

- **[`structured_log_e2e`](packages/e2e/)** — end-to-end tests that run
  the real server as a subprocess and drive it through
  `structured_log`/`HttpLogOutput` on the way in and the admin client's
  own repositories/`ApiClient` on the way out, covering the seams unit
  and integration tests each stop short of. Not published — a test
  harness, not a library.

## Repository Layout

Packages are grouped by top-level category, each listed by its full path
in [melos.yaml](melos.yaml): `emb/` for libraries meant to be embedded in
another app (`structured_log` and its log-viewer skins, `structured_log_http`),
`backend/` for standalone server apps (`structured_log_server`), `frontend/`
for standalone client apps with a UI (`structured_log_admin_ui`,
`structured_log_admin_client`), and `packages/` for anything that doesn't
fit the three categories above (`structured_log_e2e`, end-to-end tests
across the whole system). See [AGENTS.md](AGENTS.md) for the full
toolchain reference (commands, conventions, versioning, CI) if you're
contributing.

**New to the server system?** Start with
[docs/guides/](docs/guides/README.md) — a User Guide, an
Administrator/DevOps Guide, a Developer Guide, and a Contributor Guide,
each answering "how do I actually do this" for its audience. [docs/](docs/)
also holds the cross-package *design* documentation for the server system — HTTP API
and JSON models, authentication and RBAC, storage, live streaming,
quotas, and operational configuration — in bilingual pairs; see
[docs/README.md](docs/README.md) for the full table of contents.

**[`site/`](site/)** publishes that same [docs/](docs/) content as a
browsable, searchable website (English/Russian) — an
[Astro](https://astro.build)+[Starlight](https://starlight.astro.build)
project, outside the Dart/Flutter Melos workspace. It's generated from
`docs/` by a script, not hand-authored; see [site/README.md](site/README.md).
Run it locally with:

```bash
cd site && npm install && npm run dev
```

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

Logging, with the core library alone:

```dart
import 'package:structured_log/structured_log.dart';

void main() {
  final log = getLogger();
  log.info('user_login', context: {'user_id': 42, 'ip': '127.0.0.1'});
}
```

Shipping those entries to a server instead of (or alongside) the console:

```dart
final output = HttpLogOutput(
  serverUrl: 'https://logs.example.com',
  projectSecretKey: 'slk_...',
);
StructlogConfiguration.configure(
  sinks: [LogSink(name: 'server', output: output)],
);
```

Running that server — see
[backend/structured_log_server/README.md](backend/structured_log_server/README.md)
for the path from an empty database to a queried log entry:

```bash
export STRUCTURED_LOG_JWT_SECRET="$(openssl rand -base64 48 | tr -d '\n')"
dart run bin/server.dart serve --db-path=./logs.sqlite
```

See each package's own README for installation and full API reference.

## License

MIT — see [LICENSE](LICENSE).
