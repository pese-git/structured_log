import 'processors.dart';
import 'formatters.dart';

/// Configuration for structlog
class StructlogConfiguration {
  final List<Processor> processors;
  final OutputFunction output;
  final Map<String, dynamic> initialContext;

  StructlogConfiguration({
    this.processors = const [dropNullValues],
    this.output = defaultOutput,
    this.initialContext = const {},
  });

  static StructlogConfiguration _current = StructlogConfiguration();

  static StructlogConfiguration get current => _current;

  /// Configure structlog globally
  static void configure({
    List<Processor>? processors,
    OutputFunction? output,
    Map<String, dynamic>? initialContext,
  }) {
    _current = StructlogConfiguration(
      processors: processors ?? _current.processors,
      output: output ?? _current.output,
      initialContext: initialContext ?? _current.initialContext,
    );
  }

  /// Reset to default configuration
  static void reset() {
    _current = StructlogConfiguration();
  }
}
