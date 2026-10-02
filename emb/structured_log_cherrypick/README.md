# structured_log_cherrypick

[![CI](https://github.com/pese-git/structured_log/actions/workflows/ci.yml/badge.svg)](https://github.com/pese-git/structured_log/actions/workflows/ci.yml)

*Читать на [русском](README.ru.md).*

Logs what the [`cherrypick`](https://pub.dev/packages/cherrypick) DI
container does — scopes opening and closing, modules installed, dependency
cycles, resolve errors — as
[`structured_log`](https://pub.dev/packages/structured_log) entries.

`StructuredLogCherryPickObserver` is an ordinary `CherryPickObserver`:
install it as the container's global observer, and the container reports
through the sinks you have already configured — the console, a file, the
in-app log viewer (`structured_log_flutter`), or a `structured_log_server`
via `structured_log_remote_sync`. It is how a wiring that silently did not happen
shows up: a scope that never opened, a module that was never installed.

## Features

- **One line to install** — `CherryPick.setGlobalObserver(StructuredLogCherryPickObserver())`
- **Quiet by default, loud when it matters** — scopes, modules and
  disposals at `debug`; cycles and errors at `error`, warnings at
  `warning`; the per-resolve chatter off
- **Never prints an instance** — only the name and type it is bound under;
  an error by its type, not its text
- **Its own category** — every entry carries `category: 'di'`
- **A level per hook** — or `null` to turn one off; turn resolution
  tracing on when you need it
- **Never breaks a resolve** — a logger that throws costs the entry, not
  the container's work
- **Works with `cherrypick` 3.x and 4.x** — pure Dart, no Flutter needed

## Installation

Not yet published to pub.dev (`0.1.0-dev.0`) — depend on it as a path or
git dependency for now:

```yaml
dependencies:
  cherrypick: ">=3.0.0 <5.0.0"
  structured_log: ^0.2.1
  structured_log_cherrypick:
    path: ../structured_log_cherrypick # within this monorepo
```

## Quick Start

```dart
import 'package:cherrypick/cherrypick.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_cherrypick/structured_log_cherrypick.dart';

void main() {
  StructlogConfiguration.configure(
    sinks: [LogSink(name: 'console', output: coloredConsoleOutput)],
  );
  // Before the first scope: a scope takes the global observer when it is
  // created.
  CherryPick.setGlobalObserver(StructuredLogCherryPickObserver());

  CherryPick.openRootScope().installModules([AppModule()]);
}
```

```text
DEBUG: di.scope_opened      {"category":"di","scope":"scope_1790868703933_1"}
DEBUG: di.modules_installed {"category":"di","modules":["AppModule"],"scope":"scope_1790868703933_1"}
```

To hear one scope only, hand the observer to it:
`Scope(null, observer: StructuredLogCherryPickObserver())`.

[example/main.dart](example/main.dart) opens and closes a feature scope
and resolves a binding nobody registered (`dart run example/main.dart`).

## What gets logged

| Entry                  | Default level | Fields |
|------------------------|---------------|--------|
| `di.scope_opened`      | `debug`       | `scope` |
| `di.scope_closed`      | `debug`       | `scope` |
| `di.modules_installed` | `debug`       | `modules`, `scope` |
| `di.modules_removed`   | `debug`       | `modules`, `scope` |
| `di.instance_disposed` | `debug`       | `type`, `name`, `scope` |
| `di.cycle_detected`    | `error`       | `chain`, `scope` |
| `di.warning`           | `warning`     | `message` |
| `di.error`             | `error`       | `message`, `error` (its type), `stack_trace` |
| `di.binding_registered`, `di.instance_requested`, `di.instance_created`, `di.cache_hit`, `di.cache_miss` | off | `type`, `name`, `scope` |
| `di.diagnostic`        | off           | `message` |

Every entry also carries `category` (`di`) and `logger` (`di`). `scope` is
left out when the container does not name one.

What the container itself does and does not report — the same in 3.0 and
4.0-dev:

- a scope is named by the id the container gives it
  (`scope_1790868703933_1`), not the name it was opened under;
- `di.scope_closed` comes only for a sub-scope closed through its parent
  (`closeSubScope`), not for the root scope;
- `onInstanceDisposed`, `onCacheHit` and `onCacheMiss` are part of the
  interface but are never called; the observer handles them for the day
  they are;
- a failed resolve is reported twice, once without the error object and
  once with it.

## Keeping secrets out of the log

A container holds the app's configuration, API clients and token stores,
and an object printed is whatever it holds printed. So:

- **an instance is never logged** — not on creation, not on disposal —
  only the name and type it is bound under;
- **an error is logged by its type** (`StateError`), not its text, and with
  its stack trace;
- **the `details` of a warning or a diagnostic are left out**; only the
  container's message is kept.

## Configuration

```dart
StructuredLogCherryPickObserver(
  // Trace every resolve; null turns a hook off.
  levels: const DiLogLevels(
    instanceRequested: LogLevel.trace,
    instanceCreated: LogLevel.trace,
    scopeOpened: null,
  ),
  logger: getLogger('server'),
  category: 'wiring',
);
```

It implements `CherryPickObserver` rather than extending
`SilentCherryPickObserver`: the container skips calling an observer that is
one, which would silence it too.

## API Reference

| Symbol | Description |
|---|---|
| `StructuredLogCherryPickObserver({logger, loggerName, category, levels})` | The observer. Without `logger` it calls `getLogger(loggerName)` (`di`) on every entry, so a later `StructlogConfiguration.configure` reaches it too. `category: null` binds no category. |
| `DiLogLevels({scopeOpened, scopeClosed, modulesInstalled, modulesRemoved, bindingRegistered, instanceRequested, instanceCreated, instanceDisposed, cacheHit, cacheMiss, cycleDetected, diagnostic, warning, error})` | A `LogLevel?` per hook; `null` turns it off. |

## Related packages

The rest of the `structured_log` family:

**Core**

- [`structured_log`](https://pub.dev/packages/structured_log) — structured JSON logging with context binding, processors and multi-sink routing

**In-app log viewer**

- [`structured_log_flutter`](https://pub.dev/packages/structured_log_flutter) — headless viewer core: `LogBuffer` and `LogViewerController`
- [`structured_log_material`](https://pub.dev/packages/structured_log_material) — Material 3 log viewer
- [`structured_log_fluent`](https://pub.dev/packages/structured_log_fluent) — Fluent UI (WinUI-style) log viewer
- [`structured_log_cupertino`](https://pub.dev/packages/structured_log_cupertino) — Cupertino (iOS-style) log viewer

**Shipping logs to a server**

- [`structured_log_remote_sync`](https://pub.dev/packages/structured_log_remote_sync) — batching, retrying sink for a self-hosted `structured_log_server`

**Integrations**

- [`structured_log_bloc`](https://pub.dev/packages/structured_log_bloc) — `BlocObserver` for `bloc`/`flutter_bloc`
- [`structured_log_dio`](https://pub.dev/packages/structured_log_dio) — `dio` interceptor that logs HTTP calls
- [`structured_log_http_client`](https://pub.dev/packages/structured_log_http_client) — `package:http` client wrapper that logs HTTP calls
- [`structured_log_go_router`](https://pub.dev/packages/structured_log_go_router) — logs `go_router` navigation

## License

See [LICENSE](LICENSE).
