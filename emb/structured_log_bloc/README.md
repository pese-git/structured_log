# structured_log_bloc

[![CI](https://github.com/pese-git/structured_log/actions/workflows/ci.yml/badge.svg)](https://github.com/pese-git/structured_log/actions/workflows/ci.yml)

*Читать на [русском](README.ru.md).*

**See what every bloc and cubit in your app did — each event, state change
and error as a structured log entry — with one line of setup.**

Documentation: [structured-log.openidealab.com](https://structured-log.openidealab.com).

## Why

"Why did the screen show *that*?" is the question a bloc app keeps asking,
and answering it means reconstructing what happened: which event arrived,
what state it led to, which handler threw. Without a record you add `print`
calls, reproduce the bug, and remove them again — and on a user's device you
can't do even that.

`StructuredLogBlocObserver` keeps the record for you. Installed once as
`Bloc.observer`, it writes the creation, events, transitions, errors and
closing of every bloc and cubit as `structured_log` entries — with the
bloc's type, its instance and the values involved as separate fields, so you
can filter the story of one bloc out of everything else.

## Features

### Coverage

- **One line to install** — `Bloc.observer = StructuredLogBlocObserver()`.
- **Every hook** — creation, events, transitions, cubit changes, errors with
  stack traces, handler completion, closing.
- **Each state change once** — a bloc's change is logged as a transition
  (with its event), a cubit's as a change; never both.
- **Instances told apart** — `bloc_instance` separates two blocs of the same
  type.
- **Works with `flutter_bloc` as is** — depends on `package:bloc` only, which
  `flutter_bloc` is built on, so it also runs in pure Dart.

### Control

- **Its own category** — every entry carries `category: 'bloc'`, so a
  `LogSink` can route bloc traffic separately and the in-app log viewer
  offers it as a filter.
- **A level per hook** — or `null` to turn a hook off.
- **A filter** — leave noisy blocs out of the log entirely.
- **Values under your control** — states and events go through a describer
  you can replace, to keep secrets out of the log or hand `redactKeys` a map.

### Safety

- **Never breaks a bloc** — a `toString()` or describer that throws costs the
  entry its values, not the bloc its `emit`.
- **Costs nothing when off** — a hook that is off or a bloc that is filtered
  out never has its state described.

## Where it fits

The observer needs nothing but
[`structured_log`](https://pub.dev/packages/structured_log) — no server, no
Flutter. Its entries flow to whatever sinks you have configured: the
console, a file, an in-app log viewer
([`structured_log_material`](https://pub.dev/packages/structured_log_material),
[`structured_log_fluent`](https://pub.dev/packages/structured_log_fluent) or
[`structured_log_cupertino`](https://pub.dev/packages/structured_log_cupertino)),
where the `bloc` category becomes a filter, or a self-hosted
`structured_log_server` through
[`structured_log_remote_sync`](https://pub.dev/packages/structured_log_remote_sync).
It is one of five adapters that log what your app's libraries already do;
the whole project is at
[structured-log.openidealab.com](https://structured-log.openidealab.com).

## Installation

Published on pub.dev as a pre-release:

```yaml
dependencies:
  flutter_bloc: ^9.0.0 # or bloc: ^9.0.0
  structured_log: ^0.3.0
  structured_log_bloc: ^0.1.0-dev.3
```

## Quick Start

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_bloc/structured_log_bloc.dart';

void main() {
  StructlogConfiguration.configure(
    sinks: [LogSink(name: 'console', output: coloredConsoleOutput)],
  );
  Bloc.observer = StructuredLogBlocObserver();

  runApp(const MyApp());
}
```

A `CounterBloc` receiving one `Incremented` event then logs:

```text
[2026-10-02T16:04:41.519257Z] DEBUG: bloc_created {"logger":"bloc","category":"bloc","bloc":"CounterBloc","bloc_instance":787006492,"state":"0","state_type":"int"}
[2026-10-02T16:04:41.527204Z] DEBUG: bloc_event_added {"logger":"bloc","category":"bloc","bloc":"CounterBloc","bloc_instance":787006492,"bloc_event":"Incremented()","bloc_event_type":"Incremented"}
[2026-10-02T16:04:41.531119Z] DEBUG: bloc_transition {"logger":"bloc","category":"bloc","bloc":"CounterBloc","bloc_instance":787006492,"bloc_event":"Incremented()","bloc_event_type":"Incremented","current_state":"0","next_state":"1","state_type":"int"}
```

See [example/main.dart](example/main.dart) for a runnable version
(`dart run example/main.dart`).

## What gets logged

Every entry carries `category` (`bloc` by default), `logger` (`bloc` by
default), `bloc` — the bloc's type — and `bloc_instance`, its identity, which
tells apart two instances of the same type.

| Hook           | `event`            | Default level | Fields |
|----------------|--------------------|---------------|--------|
| `onCreate`     | `bloc_created`     | `debug`       | `state`, `state_type` |
| `onEvent`      | `bloc_event_added` | `debug`       | `bloc_event`, `bloc_event_type` |
| `onChange`     | `bloc_change`      | `debug`       | `current_state`, `next_state`, `state_type` — **cubits only** |
| `onTransition` | `bloc_transition`  | `debug`       | `bloc_event`, `bloc_event_type`, `current_state`, `next_state`, `state_type` |
| `onError`      | `bloc_error`       | `error`       | `error`, `error_type`, `stack_trace` |
| `onDone`       | `bloc_event_done`  | `trace`       | `bloc_event`, `bloc_event_type`; `error`, `error_type` if the handler failed |
| `onClose`      | `bloc_closed`      | `debug`       | — |

The bloc's event sits under `bloc_event`, not `event`: in `structured_log`
`event` is the entry's own name.

`bloc_event_done` is at `trace`, which a sink's default `minLevel` (`debug`)
filters out — it repeats the event of every handler, which is rarely worth
the volume. Lower a sink's `minLevel` to see it.

## Keeping secrets out of the log

**States and events are logged through `toString()` by default** (cut to
1000 characters). If they can carry passwords, tokens or personal data —
and especially if the log leaves the device through `structured_log_remote_sync` —
pass a `describe` that withholds them. Returning `null` drops the value and
keeps its type:

```dart
Bloc.observer = StructuredLogBlocObserver(
  describe: (value) => switch (value) {
    AuthState() || LoginSubmitted() => null,
    _ => describeBlocValue(value),
  },
);
```

To log types only, everywhere: `describe: (_) => null`.

A `describe` can also return a **map** instead of a string. A map stays a
structure in the entry, so a `redactKeys` processor reaches its fields, as it
reaches any other field. A string from `toString()` is opaque to it:

```dart
StructlogConfiguration.configure(processors: [redactKeys(), dropNullValues]);

Bloc.observer = StructuredLogBlocObserver(
  describe: (value) => switch (value) {
    AuthState(:final user, :final token) => {'user': user, 'token': token},
    _ => describeBlocValue(value),
  },
);
// next_state: {"user": "u", "token": "***"}
```

## Configuration

```dart
Bloc.observer = StructuredLogBlocObserver(
  // Which hooks are logged, and at what level; null turns one off.
  levels: const BlocLogLevels(
    event: LogLevel.trace,
    transition: LogLevel.info,
    done: null,
  ),
  // Leave noisy blocs out.
  filter: (bloc) => bloc is! TickerCubit,
  category: 'state',
);
```

Several observers at once — this one and, say, a crash reporter — combine
through `bloc`'s own `MultiBlocObserver` (`bloc` 9.2.0 or later).

## API Reference

| Symbol | Description |
|---|---|
| `StructuredLogBlocObserver({logger, loggerName, category, levels, describe, filter})` | The observer. Without `logger`, it calls `getLogger(loggerName)` on every hook, so a later `StructlogConfiguration.configure` reaches it too. `category: null` binds no category. |
| `BlocLogLevels({create, event, change, transition, error, done, close})` | A `LogLevel?` per hook; `null` turns the hook off. |
| `BlocValueDescriber` | `Object? Function(Object? value)` — turns a state, event or error into an entry value; `null` omits the field. |
| `describeBlocValue(value)` | The default describer: `toString()`, cut to `defaultBlocValueMaxLength` (1000) characters; a throwing `toString()` becomes a placeholder. |

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

- [`structured_log_dio`](https://pub.dev/packages/structured_log_dio) — `dio` interceptor that logs HTTP calls
- [`structured_log_http_client`](https://pub.dev/packages/structured_log_http_client) — `package:http` client wrapper that logs HTTP calls
- [`structured_log_go_router`](https://pub.dev/packages/structured_log_go_router) — logs `go_router` navigation
- [`structured_log_cherrypick`](https://pub.dev/packages/structured_log_cherrypick) — observer for the `cherrypick` DI container

## License

MIT — see [LICENSE](LICENSE).
