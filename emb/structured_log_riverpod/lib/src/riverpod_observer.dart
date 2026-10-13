import 'package:riverpod/misc.dart' show ProviderBase;
import 'package:riverpod/riverpod.dart';
import 'package:structured_log/structured_log.dart';

/// Turns a provider's value or argument into a value for a log entry.
///
/// Returning `null` leaves the field out of the entry altogether — the type
/// (`value_type`) is still logged, so an entry stays readable even when its
/// value is withheld.
typedef RiverpodValueDescriber = Object? Function(Object? value);

/// The longest string [describeRiverpodValue] keeps before cutting it short.
const int defaultRiverpodValueMaxLength = 1000;

/// The default [RiverpodValueDescriber]: `toString()`, cut to
/// [defaultRiverpodValueMaxLength] characters.
///
/// A string rather than the object itself, because an entry travels on to
/// sinks that encode it as JSON (a file, `RemoteSyncLogOutput`), and an
/// arbitrary state object is not something `jsonEncode` can take. A
/// `toString()` that throws yields a placeholder instead of the exception:
/// the observer runs inside Riverpod's own notification, and logging must
/// never break it.
Object? describeRiverpodValue(Object? value) {
  if (value == null) return null;
  final String text;
  try {
    text = value.toString();
  } catch (error) {
    return '<${value.runtimeType}.toString() threw ${error.runtimeType}>';
  }
  return text.length <= defaultRiverpodValueMaxLength
      ? text
      : '${text.substring(0, defaultRiverpodValueMaxLength)}…';
}

/// The level each [StructuredLogRiverpodObserver] hook logs at; `null` turns
/// a hook off.
///
/// Updates are the most frequent event — a provider bound to a text field or
/// a stream updates all the time — so `RiverpodLogLevels(updated: null)` is
/// the usual way to quiet the observer without losing failures.
class RiverpodLogLevels {
  /// A provider was created.
  final LogLevel? added;

  /// A provider's value changed.
  final LogLevel? updated;

  /// A provider failed — it threw while building, or its future or stream
  /// ended with an error.
  final LogLevel? failed;

  /// A provider was removed from memory.
  final LogLevel? disposed;

  const RiverpodLogLevels({
    this.added = LogLevel.debug,
    this.updated = LogLevel.debug,
    this.failed = LogLevel.error,
    this.disposed = LogLevel.debug,
  });
}

/// A [ProviderObserver] that writes what every Riverpod provider does to
/// `structured_log`.
///
/// Pass it to the container, once:
///
/// ```dart
/// StructlogConfiguration.configure(
///   sinks: [LogSink(name: 'console', output: coloredConsoleOutput)],
/// );
/// final container = ProviderContainer(
///   observers: [StructuredLogRiverpodObserver()],
/// );
/// ```
///
/// In a Flutter app the same observer goes to
/// `ProviderScope(observers: [...])`. Riverpod 3 only: the hooks of 2.x have
/// other signatures.
///
/// Each hook produces one entry, tagged with [category] (so a `LogSink` can
/// route provider traffic on its own, and the in-app log viewer offers it as
/// a filter). The provider is named under `provider` — its `name`, or its type
/// when it has none — and a family's argument under `provider_argument`:
///
/// | hook                | event               | fields                                           |
/// |---------------------|---------------------|--------------------------------------------------|
/// | `didAddProvider`    | `provider_added`    | `value`, `value_type`                            |
/// | `didUpdateProvider` | `provider_updated`  | `previous_value`, `value`, `value_type`          |
/// | `providerDidFail`   | `provider_failed`   | `error`, `error_type`, `stack_trace`             |
/// | `didUnmountProvider`| `provider_disposed` | —                                                |
///
/// An asynchronous provider that fails is reported by Riverpod twice — as an
/// update to `AsyncError` and then as a failure — so that update is left out
/// and every failure appears exactly once, as `provider_failed`.
///
/// `provider_disposed` is written when a provider is removed from memory, not
/// when it rebuilds. That hook, `didUnmountProvider`, exists from `riverpod`
/// 3.3.2: on 3.0.0–3.2.1 the entry is not written at all.
///
/// **Values and family arguments are logged through `toString()` by
/// default.** If they can carry passwords, tokens or personal data, pass a
/// [describe] that withholds them — returning `null` drops the value and keeps
/// the type:
///
/// ```dart
/// StructuredLogRiverpodObserver(
///   describe: (value) => value is Session ? null : describeRiverpodValue(value),
/// );
/// ```
final class StructuredLogRiverpodObserver extends ProviderObserver {
  final BoundLogger? _logger;

  /// The name passed to `getLogger` when no logger was given; it lands in
  /// the `logger` field of every entry.
  final String loggerName;

  /// Bound under `category` on every entry; `null` binds nothing, leaving
  /// whatever category the logger already carries.
  final String? category;

  /// The level of each hook; see [RiverpodLogLevels].
  final RiverpodLogLevels levels;

  /// Turns values and family arguments into entry values; see
  /// [describeRiverpodValue].
  final RiverpodValueDescriber describe;

  /// When given, only providers for which it returns `true` are logged.
  final bool Function(ProviderBase<Object?> provider)? filter;

  /// Creates the observer.
  ///
  /// Without a [logger] it calls `getLogger(loggerName)` on every hook
  /// rather than once, so a later `StructlogConfiguration.configure` takes
  /// effect for providers too — a `BoundLogger` keeps the configuration it
  /// was created with, and this observer usually outlives the first one.
  StructuredLogRiverpodObserver({
    BoundLogger? logger,
    this.loggerName = 'riverpod',
    this.category = 'riverpod',
    this.levels = const RiverpodLogLevels(),
    this.describe = describeRiverpodValue,
    this.filter,
  }) : _logger = logger;

  @override
  void didAddProvider(ProviderObserverContext context, Object? value) {
    _log(context, levels.added, 'provider_added', () => _valueOf(value));
  }

  @override
  void didUpdateProvider(
    ProviderObserverContext context,
    Object? previousValue,
    Object? newValue,
  ) {
    // Riverpod reports a failing future or stream twice: this update to
    // AsyncError, then providerDidFail. The failure carries the stack trace.
    if (newValue is AsyncError) return;
    _log(context, levels.updated, 'provider_updated', () {
      return {
        ..._value('previous_value', previousValue),
        ..._valueOf(newValue),
      };
    });
  }

  @override
  void providerDidFail(
    ProviderObserverContext context,
    Object error,
    StackTrace stackTrace,
  ) {
    _log(
      context,
      levels.failed,
      'provider_failed',
      () => const {},
      error: error,
      stackTrace: stackTrace,
    );
  }

  /// Not `didDisposeProvider`: that one fires on every rebuild — a changed
  /// dependency, `refresh`, `invalidate` — sometimes twice, and says nothing
  /// about the provider going away.
  @override
  void didUnmountProvider(ProviderObserverContext context) {
    _log(context, levels.disposed, 'provider_disposed', () => const {});
  }

  /// Builds the entry only once it is known to be wanted: describing a
  /// large value is the expensive part, and a hook that is off, a provider
  /// that is filtered out or a level no sink takes should cost nothing.
  ///
  /// A [describe] that throws costs the entry its values, and a [filter]
  /// that throws costs the entry, but neither costs the provider its state
  /// change: the hooks run inside Riverpod's notification, so an exception
  /// here would surface in application code that never asked to be logged.
  void _log(
    ProviderObserverContext context,
    LogLevel? level,
    String event,
    Map<String, dynamic> Function() fields, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (level == null) return;
    try {
      final provider = context.provider;
      if (filter != null && !filter!(provider)) return;
      final logger = _logger ?? getLogger(loggerName);
      if (!logger.isEnabled(level)) return;

      Map<String, dynamic> described;
      try {
        described = {
          ..._value('provider_argument', provider.argument),
          ...fields(),
        };
      } catch (thrown) {
        described = {'describe_failed': thrown.runtimeType.toString()};
      }
      logger.tryLog(
        level,
        event,
        context: {
          if (category != null) 'category': category,
          'provider': provider.name ?? provider.runtimeType.toString(),
          ...described,
        },
        error: error,
        stackTrace: stackTrace,
      );
    } catch (_) {
      // A throwing filter or logger: the entry is lost, the provider is not.
    }
  }

  Map<String, dynamic> _valueOf(Object? value) => {
    ..._value('value', value),
    'value_type': value.runtimeType.toString(),
  };

  /// [key] with the described [value], or nothing if [describe] withheld
  /// it.
  Map<String, dynamic> _value(String key, Object? value) {
    final described = describe(value);
    return described == null ? const {} : {key: described};
  }
}
