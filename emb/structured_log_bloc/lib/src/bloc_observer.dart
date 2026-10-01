import 'package:bloc/bloc.dart';
import 'package:structured_log/structured_log.dart';

/// Turns a bloc's state, event or error into a value for a log entry.
///
/// Returning `null` leaves the field out of the entry altogether — the type
/// (`state_type`, `bloc_event_type`) is still logged, so an entry stays readable
/// even when its value is withheld.
typedef BlocValueDescriber = Object? Function(Object? value);

/// The longest string [describeBlocValue] keeps before cutting it short.
const int defaultBlocValueMaxLength = 1000;

/// The default [BlocValueDescriber]: `toString()`, cut to
/// [defaultBlocValueMaxLength] characters.
///
/// A string rather than the object itself, because an entry travels on to
/// sinks that encode it as JSON (a file, `RemoteSyncLogOutput`), and an arbitrary
/// state object is not something `jsonEncode` can take. A `toString()` that
/// throws yields a placeholder instead of the exception: the observer runs
/// inside the bloc's own `emit`/`add`, and logging must never break them.
Object? describeBlocValue(Object? value) {
  if (value == null) return null;
  final String text;
  try {
    text = value.toString();
  } catch (error) {
    return '<${value.runtimeType}.toString() threw ${error.runtimeType}>';
  }
  return text.length <= defaultBlocValueMaxLength
      ? text
      : '${text.substring(0, defaultBlocValueMaxLength)}…';
}

/// The level each [StructuredLogBlocObserver] hook logs at; `null` turns a
/// hook off.
///
/// The defaults keep the routine traffic — creation, events, transitions —
/// at `debug`, where a sink's default `minLevel` still lets it through, and
/// [done] at `trace`, which is off unless a sink opts in: it repeats the
/// event of every handler that finishes, which is rarely worth the volume.
class BlocLogLevels {
  /// A bloc or cubit was constructed.
  final LogLevel? create;

  /// An event was added to a bloc.
  final LogLevel? event;

  /// A cubit emitted a new state. Not used for blocs — their state changes
  /// are logged as [transition], which also names the event.
  final LogLevel? change;

  /// A bloc moved to a new state in response to an event.
  final LogLevel? transition;

  /// `addError` was called, or an event handler threw.
  final LogLevel? error;

  /// An event handler finished, successfully or not.
  final LogLevel? done;

  /// A bloc or cubit was closed.
  final LogLevel? close;

  const BlocLogLevels({
    this.create = LogLevel.debug,
    this.event = LogLevel.debug,
    this.change = LogLevel.debug,
    this.transition = LogLevel.debug,
    this.error = LogLevel.error,
    this.done = LogLevel.trace,
    this.close = LogLevel.debug,
  });
}

/// A [BlocObserver] that writes what every bloc and cubit does to
/// `structured_log`.
///
/// Install it once, before any bloc is created:
///
/// ```dart
/// StructlogConfiguration.configure(
///   sinks: [LogSink(name: 'console', output: coloredConsoleOutput)],
/// );
/// Bloc.observer = StructuredLogBlocObserver();
/// ```
///
/// Each hook produces one entry, tagged with [category] (so a `LogSink` can
/// route bloc traffic on its own, and the in-app log viewer offers it as a
/// filter), the bloc's type under `bloc` and its identity under
/// `bloc_instance` — two instances of the same type are told apart by the
/// latter:
///
/// | hook           | event              | fields                                         |
/// |----------------|--------------------|------------------------------------------------|
/// | `onCreate`     | `bloc_created`     | `state`, `state_type`                          |
/// | `onEvent`      | `bloc_event_added` | `bloc_event`, `bloc_event_type`                |
/// | `onChange`     | `bloc_change`      | `current_state`, `next_state`, `state_type` — cubits only |
/// | `onTransition` | `bloc_transition`  | `bloc_event`, `bloc_event_type`, `current_state`, `next_state`, `state_type` |
/// | `onError`      | `bloc_error`       | `error`, `error_type`, `stack_trace`           |
/// | `onDone`       | `bloc_event_done`  | `bloc_event`, `bloc_event_type`, and `error`/`error_type` if the handler failed |
/// | `onClose`      | `bloc_closed`      | —                                              |
///
/// A bloc's state change reaches the observer twice — as `onTransition` and
/// then as `onChange` — so `onChange` is logged for cubits only, and every
/// state change appears exactly once.
///
/// **States and events are logged through `toString()` by default.** If
/// they can carry passwords, tokens or personal data, pass a [describe]
/// that withholds them — returning `null` drops the value and keeps the
/// type:
///
/// ```dart
/// Bloc.observer = StructuredLogBlocObserver(
///   describe: (value) => value is AuthState ? null : describeBlocValue(value),
/// );
/// ```
class StructuredLogBlocObserver extends BlocObserver {
  final BoundLogger? _logger;

  /// The name passed to `getLogger` when no logger was given; it lands in
  /// the `logger` field of every entry.
  final String loggerName;

  /// Bound under `category` on every entry; `null` binds nothing, leaving
  /// whatever category the logger already carries.
  final String? category;

  /// The level of each hook; see [BlocLogLevels].
  final BlocLogLevels levels;

  /// Turns states, events and errors into entry values; see
  /// [describeBlocValue].
  final BlocValueDescriber describe;

  /// When given, only blocs for which it returns `true` are logged.
  final bool Function(BlocBase<dynamic> bloc)? filter;

  /// Creates the observer.
  ///
  /// Without a [logger] it calls `getLogger(loggerName)` on every hook
  /// rather than once, so a later `StructlogConfiguration.configure` takes
  /// effect for blocs too — a `BoundLogger` keeps the configuration it was
  /// created with, and this observer usually outlives the first one.
  StructuredLogBlocObserver({
    BoundLogger? logger,
    this.loggerName = 'bloc',
    this.category = 'bloc',
    this.levels = const BlocLogLevels(),
    this.describe = describeBlocValue,
    this.filter,
  }) : _logger = logger;

  @override
  void onCreate(BlocBase<dynamic> bloc) {
    super.onCreate(bloc);
    _log(bloc, levels.create, 'bloc_created', () {
      final state = bloc.state;
      return {
        ..._value('state', state),
        'state_type': _typeOf(state),
      };
    });
  }

  @override
  void onEvent(Bloc<dynamic, dynamic> bloc, Object? event) {
    super.onEvent(bloc, event);
    _log(bloc, levels.event, 'bloc_event_added', () => _event(event));
  }

  @override
  void onChange(BlocBase<dynamic> bloc, Change<dynamic> change) {
    super.onChange(bloc, change);
    // A bloc's change was already logged by onTransition, with its event.
    if (bloc is Bloc) return;
    _log(bloc, levels.change, 'bloc_change', () => _change(change));
  }

  @override
  void onTransition(
    Bloc<dynamic, dynamic> bloc,
    Transition<dynamic, dynamic> transition,
  ) {
    super.onTransition(bloc, transition);
    _log(bloc, levels.transition, 'bloc_transition', () {
      return {..._event(transition.event), ..._change(transition)};
    });
  }

  @override
  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    super.onError(bloc, error, stackTrace);
    _log(bloc, levels.error, 'bloc_error', () {
      return {..._error(error), 'stack_trace': stackTrace.toString()};
    });
  }

  @override
  void onDone(
    Bloc<dynamic, dynamic> bloc,
    Object? event, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    super.onDone(bloc, event, error, stackTrace);
    // The stack trace is left out: a failed handler also reaches onError,
    // which logs it once.
    _log(bloc, levels.done, 'bloc_event_done', () {
      return {..._event(event), if (error != null) ..._error(error)};
    });
  }

  @override
  void onClose(BlocBase<dynamic> bloc) {
    super.onClose(bloc);
    _log(bloc, levels.close, 'bloc_closed', () => const {});
  }

  /// Builds the entry only once it is known to be wanted: describing a
  /// large state is the expensive part, and a hook that is off or a bloc
  /// that is filtered out should cost nothing.
  ///
  /// A [describe] that throws costs the entry its values, not the bloc its
  /// `emit`: the hooks run inside the bloc, so an exception here would
  /// surface in application code that never asked to be logged.
  void _log(
    BlocBase<dynamic> bloc,
    LogLevel? level,
    String event,
    Map<String, dynamic> Function() fields,
  ) {
    if (level == null) return;
    if (filter != null && !filter!(bloc)) return;
    Map<String, dynamic> described;
    try {
      described = fields();
    } catch (error) {
      described = {'describe_failed': error.runtimeType.toString()};
    }
    (_logger ?? getLogger(loggerName)).tryLog(
      level,
      event,
      context: {
        if (category != null) 'category': category,
        'bloc': bloc.runtimeType.toString(),
        'bloc_instance': identityHashCode(bloc),
        ...described,
      },
    );
  }

  /// Under `bloc_event`, not `event`: `event` is the entry's own name in
  /// `structured_log`, and the bloc's event would overwrite it.
  Map<String, dynamic> _event(Object? event) => {
        ..._value('bloc_event', event),
        'bloc_event_type': _typeOf(event),
      };

  Map<String, dynamic> _change(Change<dynamic> change) => {
        ..._value('current_state', change.currentState),
        ..._value('next_state', change.nextState),
        'state_type': _typeOf(change.nextState),
      };

  Map<String, dynamic> _error(Object error) => {
        ..._value('error', error),
        'error_type': _typeOf(error),
      };

  /// [key] with the described [value], or nothing if [describe] withheld
  /// it.
  Map<String, dynamic> _value(String key, Object? value) {
    final described = describe(value);
    return described == null ? const {} : {key: described};
  }

  static String _typeOf(Object? value) => value.runtimeType.toString();
}
