import 'package:structured_log/structured_log.dart';
import 'package:test/test.dart';

void main() {
  tearDown(StructlogConfiguration.reset);

  late List<Map<String, dynamic>> delivered;

  void captureAll({
    LogLevel minLevel = LogLevel.debug,
    Set<String>? categories,
    List<Processor>? processors,
  }) {
    delivered = [];
    StructlogConfiguration.configure(processors: processors, sinks: [
      LogSink(
        name: 'capture',
        output: (entry, level) => delivered.add(entry),
        minLevel: minLevel,
        categories: categories,
      ),
    ]);
  }

  group('isEnabled and the early exit', () {
    test('a level no sink accepts never reaches the processors', () {
      var processed = 0;
      captureAll(processors: [
        (entry) {
          processed++;
          return entry;
        },
      ]);
      final log = getLogger();

      log.trace('frame', context: {'bytes': 128});

      expect(processed, 0);
      expect(delivered, isEmpty);
      expect(log.isEnabled(LogLevel.trace), isFalse);
      expect(log.isEnabled(LogLevel.debug), isTrue);
    });

    test('a disabled sink does not count', () {
      captureAll();
      StructlogConfiguration.setSinkEnabled('capture', enabled: false);

      expect(getLogger().isEnabled(LogLevel.critical), isFalse);
    });

    test('with a category, it answers for that category', () {
      captureAll(categories: {'http'});
      final log = getLogger();

      expect(log.isEnabled(LogLevel.info, category: 'http'), isTrue);
      expect(log.isEnabled(LogLevel.info, category: 'db'), isFalse);
      expect(
        log.isEnabled(LogLevel.info),
        isTrue,
        reason: 'without a category the answer is about the level alone',
      );
    });

    test('a sink whose accepts() throws counts as accepting', () {
      StructlogConfiguration.configure(sinks: [_ThrowingAcceptsSink()]);

      expect(
        getLogger().isEnabled(LogLevel.info, category: 'x'),
        isTrue,
        reason: 'answering "off" would hide entries the sink might want',
      );
    });
  });

  group('error and stackTrace parameters', () {
    setUp(captureAll);

    test('become error, error_type and stack_trace', () {
      final stackTrace = StackTrace.current;

      getLogger().error(
        'charge_failed',
        error: StateError('timeout'),
        stackTrace: stackTrace,
      );

      final entry = delivered.single;
      expect(entry['error'], 'Bad state: timeout');
      expect(entry['error_type'], 'StateError');
      expect(entry['stack_trace'], stackTrace.toString());
    });

    test('win over the same keys in context', () {
      getLogger().critical(
        'x',
        context: {'error': 'from context', 'error_type': 'String'},
        error: const FormatException('bad'),
      );

      expect(delivered.single['error'], 'FormatException: bad');
      expect(delivered.single['error_type'], 'FormatException');
    });

    test('a stack trace alone adds only stack_trace', () {
      getLogger().warning('x', stackTrace: StackTrace.empty);

      expect(delivered.single.containsKey('error'), isFalse);
      expect(delivered.single.containsKey('error_type'), isFalse);
      expect(delivered.single.containsKey('stack_trace'), isTrue);
    });

    test('every level takes them', () {
      final log = getLogger();
      final error = StateError('e');

      log.debug('debug', error: error);
      log.info('info', error: error);
      log.warning('warning', error: error);
      log.error('error', error: error);
      log.critical('critical', error: error);
      log.tryLog(LogLevel.info, 'tryLog', error: error);

      expect(delivered.map((e) => e['error_type']), everyElement('StateError'));
      expect(delivered, hasLength(6));
    });

    test('an error whose toString() throws is named by its type', () {
      getLogger().error('x', error: _ThrowingToString());

      expect(delivered.single['error'], '<_ThrowingToString>');
      expect(delivered.single['error_type'], '_ThrowingToString');
    });
  });

  group('A logger follows the current configuration', () {
    test('when it was created before configure()', () {
      final log = getLogger();
      captureAll();

      log.info('x');

      expect(delivered.single['event'], 'x');
    });

    test('including initialContext, read when the entry is made', () {
      final log = getLogger('payments');
      captureAll();
      StructlogConfiguration.configure(
        initialContext: {'app': 'shop', 'logger': 'from initial context'},
      );

      log.info('x');

      expect(delivered.single['app'], 'shop');
      expect(delivered.single['logger'], 'payments');
    });

    test('and so do the loggers derived from it', () {
      final log = getLogger().bind({'a': 1}).withCorrelation(requestId: 'r');
      captureAll();

      log.unbind(['a']).info('x');

      expect(delivered.single['request_id'], 'r');
      expect(delivered.single.containsKey('a'), isFalse);
    });

    test('a logger given a configuration keeps it', () {
      final kept = <Map<String, dynamic>>[];
      final log = BoundLogger(
        StructlogConfiguration(output: (e, l) => kept.add(e)),
      );
      captureAll();

      log.bind({'a': 1}).info('x');

      expect(kept.single['a'], 1);
      expect(delivered, isEmpty);
    });

    test('a logger given a configuration reads isEnabled from it', () {
      final log = BoundLogger(
        StructlogConfiguration(sinks: [
          LogSink(name: 's', output: (e, l) {}, minLevel: LogLevel.error),
        ]),
      );
      captureAll();

      expect(log.isEnabled(LogLevel.info), isFalse);
    });
  });
}

class _ThrowingAcceptsSink extends LogSink {
  _ThrowingAcceptsSink() : super(name: 'bad', output: (e, l) {});

  @override
  bool accepts(LogLevel level, String? category) => throw StateError('no');
}

class _ThrowingToString {
  @override
  String toString() => throw StateError('no');
}
