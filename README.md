[![CI](https://github.com/pese-git/structured_log/actions/workflows/ci.yml/badge.svg)](https://github.com/pese-git/structured_log/actions/workflows/ci.yml)

*Читать на [русском](README.ru.md).*

# structured_log Workspace

A Melos + FVM monorepo for structured logging in Dart, inspired by
[Python's structlog](https://www.structlog.org/), plus an in-app log
viewer ecosystem for Flutter built on top of it.

## Packages

- **[`structured_log`](structured_log/)** — the core library: structured
  JSON logging with context binding, typed correlation fields, processors,
  and multi-sink output routing. Zero runtime dependencies beyond `meta`.
  Published on [pub.dev](https://pub.dev/packages/structured_log).

- **[`structured_log_flutter`](structured_log_flutter/)** — a headless
  log-viewer core for Flutter apps: a bounded `LogBuffer` that plugs
  directly into `structured_log` as a sink, and a filterable
  `LogViewerController`. No dependency on any specific design system —
  the foundation any UI skin builds on. *Not yet published.*

- **[`structured_log_material`](structured_log_material/)** — a
  ready-to-use Material 3 in-app log viewer built on
  `structured_log_flutter`: live list, search and level filtering,
  expanded-entry detail with copy, and empty states. Includes a runnable
  example app (`structured_log_material/example/`, web-capable). *Not yet
  published.*

## Repository Layout

Each package lives in its own top-level directory (no `packages/`
nesting), listed by name in [melos.yaml](melos.yaml) — see
[AGENTS.md](AGENTS.md) for the full toolchain reference (commands,
conventions, versioning, CI) if you're contributing.

Design and planning history for the Flutter log-viewer packages lives in
[openspec/changes/add-structured-log-flutter/](openspec/changes/add-structured-log-flutter/)
(why, technical decisions, requirements, task-by-task progress).

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
