import 'processors.dart';
import 'formatters.dart';
import 'sink.dart';

/// Configuration for structlog
class StructlogConfiguration {
  final List<Processor> processors;
  final List<LogSink> sinks;
  final Map<String, dynamic> initialContext;

  StructlogConfiguration({
    this.processors = const [dropNullValues],
    List<LogSink>? sinks,
    OutputFunction? output,
    this.initialContext = const {},
  }) : sinks = sinks ??
            [LogSink(name: 'default', output: output ?? defaultOutput)];

  static StructlogConfiguration _current = StructlogConfiguration();

  static StructlogConfiguration get current => _current;

  /// Configure structlog globally.
  ///
  /// Pass [sinks] to deliver each log entry to multiple destinations with
  /// independent level/category filtering. [output] remains supported as a
  /// shorthand for a single sink named `'default'` (not a breaking change).
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

  /// Reset to default configuration
  static void reset() {
    _current = StructlogConfiguration();
  }

  /// Enables or disables the sink named [name] in the current configuration,
  /// in place — no need to rebuild the configuration or existing loggers.
  static void setSinkEnabled(String name, {required bool enabled}) {
    for (final sink in _current.sinks) {
      if (sink.name == name) {
        sink.enabled = enabled;
      }
    }
  }
}
