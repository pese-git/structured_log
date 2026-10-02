// The deprecated renderers are still exercised here: they stay supported
// until they are removed, and they must not lag the outputs that replace them.
// ignore_for_file: deprecated_member_use_from_same_package

import 'dart:async';
import 'dart:convert';

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

  group('jsonLineOutput', () {
    test('prints the entry as one line of JSON', () {
      final printed = _capturePrints(() => jsonLineOutput(
            {'event': 'e', 'at': DateTime.utc(2026), 'n': 1},
            LogLevel.info,
          ));

      expect(printed, [
        '{"event":"e","at":"2026-01-01T00:00:00.000Z","n":1}',
      ]);
    });
  });

  group('logfmt', () {
    test('a value cannot forge a field or a line', () {
      final line = formatLogfmt({
        'level': 'info',
        'user': 'a" level=critical\nevent="forged',
      });

      expect(line, r'level="info" user="a\" level=critical\nevent=\"forged"');
    });

    test('escapes backslashes, tabs, returns and control characters', () {
      expect(
        formatLogfmt({'v': 'a\\b\tc\rd\u0001e\u007f\u2028'}),
        r'v="a\\b\tc\rd\u0001e\u007f\u2028"',
      );
    });

    test('keys keep only letters, digits, _ . and -', () {
      expect(formatLogfmt({'bad key=x"\n': 1}), 'bad_key_x__=1');
      expect(formatLogfmt({'': 1}), '_=1');
    });

    test('numbers, booleans and null stay bare; the rest is quoted', () {
      expect(
        formatLogfmt({
          'n': 3,
          'd': 1.5,
          'b': true,
          'z': null,
          'took': const Duration(milliseconds: 2),
          'at': DateTime.utc(2026),
          'hint': LogLevel.warning,
          'map': {'k': 'v "q"'},
          'list': [1, 'two'],
        }),
        'n=3 d=1.5 b=true z=null took=2000 '
        'at="2026-01-01T00:00:00.000Z" hint="warning" '
        r'map="{\"k\":\"v \\\"q\\\"\"}" list="[1,\"two\"]"',
      );
    });

    test('a value that cannot be encoded is named by its type', () {
      final loop = <String, dynamic>{};
      loop['self'] = loop;

      expect(
        formatLogfmt({'loop': loop, 'v': _ThrowingToString()}),
        'loop="<${loop.runtimeType}>" v="<_ThrowingToString>"',
      );
    });

    test('logfmtOutput prints one line', () {
      final printed = _capturePrints(
        () => logfmtOutput({'event': 'e', 'm': 'a\nb'}, LogLevel.info),
      );

      expect(printed, [r'event="e" m="a\nb"']);
    });
  });

  group('The deprecated renderers', () {
    test('jsonRenderer survives values jsonEncode refuses', () {
      final printed = _capturePrints(
        () => jsonRenderer({'event': 'e', 'at': DateTime.utc(2026)}),
      );

      expect(jsonDecode(printed.single)['at'], '2026-01-01T00:00:00.000Z');
    });

    test('logfmtRenderer escapes like logfmtOutput', () {
      final entry = <String, dynamic>{'m': 'a\nb'};
      late Map<String, dynamic>? result;

      final printed = _capturePrints(() => result = logfmtRenderer(entry));

      expect(printed, [r'm="a\nb"']);
      expect(result, same(entry));
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

List<String> _capturePrints(void Function() body) {
  final printed = <String>[];
  runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) => printed.add(line),
    ),
  );
  return printed;
}
