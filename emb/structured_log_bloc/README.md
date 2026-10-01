# structured_log_bloc

[![CI](https://github.com/pese-git/structured_log/actions/workflows/ci.yml/badge.svg)](https://github.com/pese-git/structured_log/actions/workflows/ci.yml)

*Читать на [русском](README.ru.md).*

Logs what every bloc and cubit does — creation, events, state changes,
errors, closing — as [`structured_log`](https://pub.dev/packages/structured_log)
entries.

`StructuredLogBlocObserver` is an ordinary `BlocObserver`: install it as
`Bloc.observer` and every bloc in the app reports through the sinks you have
already configured — the console, a file, the in-app log viewer
(`structured_log_flutter`), or a `structured_log_server` via
`structured_log_http`.

## Features

- **One line to install** — `Bloc.observer = StructuredLogBlocObserver()`
- **Works with `flutter_bloc` as is** — depends on `package:bloc` only, which
  `flutter_bloc` is built on, so it also runs in pure Dart
- **Its own category** — every entry carries `category: 'bloc'`, so a
  `LogSink` can route bloc traffic separately and the log viewer offers it as
  a filter
- **Each state change once** — a bloc's change is logged as a transition
  (with its event), a cubit's as a change; never both
- **A level per hook** — or `null` to turn a hook off
- **Values under your control** — states and events go through a describer
  you can replace, to keep secrets out of the log
- **Never breaks a bloc** — a `toString()` or describer that throws costs the
  entry its values, not the bloc its `emit`

## Installation

Not yet published to pub.dev (`0.1.0-dev.0`) — depend on it as a path or
git dependency for now:

```yaml
dependencies:
  flutter_bloc: ^9.0.0 # or bloc: ^9.0.0
  structured_log: ^0.2.1
  structured_log_bloc:
    path: ../structured_log_bloc # within this monorepo
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
DEBUG: bloc_created     {"category":"bloc","bloc":"CounterBloc","bloc_instance":621700500,"state":"0","state_type":"int"}
DEBUG: bloc_event_added {"category":"bloc","bloc":"CounterBloc","bloc_instance":621700500,"bloc_event":"Incremented()","bloc_event_type":"Incremented"}
DEBUG: bloc_transition  {"category":"bloc","bloc":"CounterBloc","bloc_instance":621700500,"bloc_event":"Incremented()","bloc_event_type":"Incremented","current_state":"0","next_state":"1","state_type":"int"}
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
and especially if the log leaves the device through `structured_log_http` —
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
through `bloc`'s own `MultiBlocObserver`.

## API Reference

| Symbol | Description |
|---|---|
| `StructuredLogBlocObserver({logger, loggerName, category, levels, describe, filter})` | The observer. Without `logger`, it calls `getLogger(loggerName)` on every hook, so a later `StructlogConfiguration.configure` reaches it too. `category: null` binds no category. |
| `BlocLogLevels({create, event, change, transition, error, done, close})` | A `LogLevel?` per hook; `null` turns the hook off. |
| `BlocValueDescriber` | `Object? Function(Object? value)` — turns a state, event or error into an entry value; `null` omits the field. |
| `describeBlocValue(value)` | The default describer: `toString()`, cut to `defaultBlocValueMaxLength` (1000) characters; a throwing `toString()` becomes a placeholder. |

## License

See [LICENSE](LICENSE).
