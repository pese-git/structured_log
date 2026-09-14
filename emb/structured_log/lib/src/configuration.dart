import 'processors.dart';
import 'formatters.dart';
import 'sink.dart';

/// Global, mutable configuration for the whole `structured_log` package:
/// which [Processor]s run on every entry, which [LogSink]s receive it, and
/// what context every logger starts with.
///
/// There is a single current instance, reachable via [current], that
/// [getLogger] reads when creating a [BoundLogger]. Change it with
/// [configure] (partial updates — unspecified fields keep their current
/// value) or restore the library defaults with [reset]. Because it's
/// process-global mutable state, tests that call [configure] should call
/// [reset] in `tearDown` so they don't leak configuration into other tests:
///
/// ```dart
/// import 'package:structured_log/structured_log.dart';
/// import 'package:test/test.dart';
///
/// void main() {
///   tearDown(() => StructlogConfiguration.reset());
///
///   test('emits the app name', () {
///     StructlogConfiguration.configure(initialContext: {'app': 'my_app'});
///     getLogger().info('startup');
///   });
/// }
/// ```
class StructlogConfiguration {
  /// Functions run, in order, on every log entry before it reaches any
  /// sink; a processor returning `null` drops the entry entirely. Defaults
  /// to `[dropNullValues]`. See [Processor].
  final List<Processor> processors;

  /// Destinations a log entry is delivered to, each with its own
  /// level/category filtering. Defaults to a single sink named `'default'`
  /// printing indented JSON to stdout ([defaultOutput]). See [LogSink].
  final List<LogSink> sinks;

  /// Context merged into every entry created through [getLogger], before
  /// that logger's own `bind()`/inline `context`/correlation fields (which
  /// override an `initialContext` key of the same name). Defaults to `{}`.
  final Map<String, dynamic> initialContext;

  StructlogConfiguration({
    this.processors = const [dropNullValues],
    List<LogSink>? sinks,
    OutputFunction? output,
    this.initialContext = const {},
  }) : sinks = sinks ??
            [LogSink(name: 'default', output: output ?? defaultOutput)];

  static StructlogConfiguration _current = StructlogConfiguration();

  /// The configuration every new [BoundLogger] (via [getLogger]) is created
  /// with. Starts as the library default and changes on [configure] /
  /// [reset].
  static StructlogConfiguration get current => _current;

  /// Replaces the global configuration ([current]) with a new one, built by
  /// overlaying the given arguments onto the existing configuration — any
  /// argument left `null` keeps its current value, so you can change just
  /// one aspect without restating the rest.
  ///
  /// Pass [sinks] to deliver each log entry to multiple destinations with
  /// independent level/category filtering. [output] remains supported as a
  /// shorthand for a single sink named `'default'` (not a breaking change);
  /// if both [sinks] and [output] are given, [sinks] wins.
  ///
  /// Loggers already created via [getLogger] keep pointing at the
  /// configuration they were built with — call [getLogger] again after
  /// [configure] to pick up the change.
  ///
  /// ```dart
  /// // Simple: JSON to a file instead of stdout.
  /// StructlogConfiguration.configure(output: fileOutput('logs/app.log'));
  ///
  /// // Advanced: route by category to independent destinations.
  /// StructlogConfiguration.configure(sinks: [
  ///   LogSink(name: 'console', output: coloredConsoleOutput),
  ///   LogSink(
  ///     name: 'protocol',
  ///     output: fileOutput('logs/protocol.log'),
  ///     categories: {'protocol'},
  ///   ),
  /// ]);
  /// ```
  static void configure({
    List<Processor>? processors,
    List<LogSink>? sinks,
    OutputFunction? output,
    Map<String, dynamic>? initialContext,
  }) {
    final nextSinks = sinks ??
        (output != null
            ? [LogSink(name: 'default', output: output)]
            : _current.sinks);
    _current = StructlogConfiguration(
      processors: processors ?? _current.processors,
      sinks: nextSinks,
      initialContext: initialContext ?? _current.initialContext,
    );
  }

  /// Restores [current] to the library default: `[dropNullValues]`
  /// processor, a single stdout JSON sink, and empty `initialContext`.
  ///
  /// Call this in `tearDown` after any test that calls [configure], so
  /// configuration doesn't leak between tests:
  ///
  /// ```dart
  /// tearDown(() => StructlogConfiguration.reset());
  /// ```
  static void reset() {
    _current = StructlogConfiguration();
  }

  /// Enables or disables the sink named [name] in the current configuration,
  /// in place — no need to rebuild the configuration or existing loggers.
  /// Does nothing if no sink with that [name] exists.
  ///
  /// ```dart
  /// StructlogConfiguration.configure(sinks: [
  ///   LogSink(name: 'console', output: coloredConsoleOutput),
  ///   LogSink(
  ///     name: 'protocol',
  ///     output: fileOutput('logs/protocol.log'),
  ///     categories: {'protocol'},
  ///   ),
  /// ]);
  ///
  /// // Later, turn the protocol sink off without rebuilding anything.
  /// StructlogConfiguration.setSinkEnabled('protocol', enabled: false);
  /// ```
  static void setSinkEnabled(String name, {required bool enabled}) {
    for (final sink in _current.sinks) {
      if (sink.name == name) {
        sink.enabled = enabled;
      }
    }
  }
}
