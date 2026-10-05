import 'dart:async';
import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_logging/structured_log_logging.dart';
import 'package:test/test.dart';

/// Collects every entry the sinks receive, at whatever level.
List<Map<String, dynamic>> captureEntries() {
  final entries = <Map<String, dynamic>>[];
  StructlogConfiguration.configure(
    sinks: [
      LogSink(
        name: 'capture',
        output: (entry, level) => entries.add(Map.of(entry)),
        minLevel: LogLevel.trace,
      ),
    ],
  );
  return entries;
}

List<String> eventsOf(List<Map<String, dynamic>> entries) =>
    [for (final entry in entries) entry['event'] as String];

/// Runs [body] in a zone that records uncaught errors, and returns them.
List<Object> uncaughtErrorsOf(void Function() body) {
  final errors = <Object>[];
  runZonedGuarded(body, (error, _) => errors.add(error));
  return errors;
}

void main() {
  late List<Map<String, dynamic>> entries;
  late Level rootLevel;
  late Level stackTraceLevel;
  late bool hierarchical;
  final bridges = <StructuredLogLoggingBridge>[];

  /// A bridge that is detached again after the test.
  StructuredLogLoggingBridge attached([StructuredLogLoggingBridge? bridge]) {
    final it = bridge ?? StructuredLogLoggingBridge();
    bridges.add(it);
    return it..attach();
  }

  setUp(() {
    rootLevel = Logger.root.level;
    stackTraceLevel = recordStackTraceAtLevel;
    hierarchical = hierarchicalLoggingEnabled;
    Logger.root.level = Level.ALL;
    entries = captureEntries();
  });

  tearDown(() {
    for (final bridge in bridges) {
      bridge.detach();
    }
    bridges.clear();
    Logger.root.level = rootLevel;
    recordStackTraceAtLevel = stackTraceLevel;
    hierarchicalLoggingEnabled = hierarchical;
    StructlogConfiguration.reset();
  });

  group('package:logging itself', () {
    // The bridge is built around this: a listener's exception does not come
    // back out of Logger.log but lands in the zone the listener was added
    // in. If it ever did come back, the guard in the bridge would have to
    // protect the caller in a different way.
    test('a throwing listener reaches its own zone, not the log() call', () {
      late StreamSubscription<LogRecord> subscription;
      final errors = uncaughtErrorsOf(() {
        subscription =
            Logger.root.onRecord.listen((_) => throw StateError('listener'));
      });
      addTearDown(() => subscription.cancel());

      expect(() => Logger('x').info('hi'), returnsNormally);
      expect(errors, [isA<StateError>()]);
    });
  });

  group('one entry per record', () {
    test('a library message keeps its text, logger and level', () {
      attached();

      Logger('postgres').info('connected');

      expect(entries, hasLength(1));
      expect(entries.single, containsPair('event', 'connected'));
      expect(entries.single, containsPair('logger', 'postgres'));
      expect(entries.single, containsPair('level', 'info'));
    });

    test('the root logger is written as root', () {
      attached();

      Logger.root.warning('low disk');

      expect(entries.single, containsPair('logger', 'root'));
      expect(entries.single, containsPair('level', 'warning'));
    });

    test('a non-string message is written as its toString(), not itself', () {
      attached();

      Logger('x').info(Uri.parse('https://example.com'));

      expect(entries.single, containsPair('event', 'https://example.com'));
      expect(entries.single.values, isNot(contains(isA<Uri>())));
    });
  });

  group('levels', () {
    test('standard levels map by value', () {
      attached();
      final log = Logger('x');

      log.finest('finest');
      log.fine('fine');
      log.config('config');
      log.info('info');
      log.warning('warning');
      log.severe('severe');
      log.shout('shout');

      expect([
        for (final e in entries) e['level']
      ], [
        'trace',
        'debug',
        'info',
        'info',
        'warning',
        'error',
        'critical',
      ]);
    });

    test('a custom level lands by its value', () {
      attached();

      Logger('x').log(const Level('NOTICE', 850), 'notice');

      expect(entries.single, containsPair('level', 'info'));
    });

    test('levelOf replaces the mapping, and null leaves a level out', () {
      attached(StructuredLogLoggingBridge(
        levelOf: (level) =>
            level == Level.FINE ? null : defaultLogLevelOf(level),
      ));

      Logger('x').fine('noise');
      Logger('x').info('signal');

      expect(eventsOf(entries), ['signal']);
    });

    test('the bridge leaves package:logging levels alone', () {
      Logger.root.level = Level.INFO;
      hierarchicalLoggingEnabled = false;
      final bridge = attached();

      Logger('x').fine('details');
      bridge.detach();

      expect(Logger.root.level, Level.INFO);
      expect(hierarchicalLoggingEnabled, isFalse);
      expect(entries, isEmpty);
    });
  });

  group('error and stack trace', () {
    test('are written in the same shape as BoundLogger.error', () {
      attached();
      final stack = StackTrace.current;

      Logger('db').severe('query failed', StateError('closed'), stack);

      final entry = entries.single;
      expect(entry, containsPair('level', 'error'));
      expect(entry, containsPair('error', 'Bad state: closed'));
      expect(entry, containsPair('error_type', 'StateError'));
      expect(entry, containsPair('stack_trace', stack.toString()));
    });

    test("package:logging's own placeholder error is left out", () {
      recordStackTraceAtLevel = Level.WARNING;
      attached();

      Logger('x').warning('slow');

      expect(entries.single, contains('stack_trace'));
      expect(entries.single.keys, isNot(contains('error')));
    });

    test('a real error that only starts like the placeholder is kept', () {
      attached();

      Logger('x').warning('slow', 'autogenerated stack trace for a reason');

      expect(
        entries.single,
        containsPair('error', 'autogenerated stack trace for a reason'),
      );
    });
  });

  group('category, context and filter', () {
    test('every entry carries the logging category by default', () {
      attached();

      Logger('x').info('m');

      expect(entries.single, containsPair('category', 'logging'));
    });

    test('a null category writes none', () {
      attached(StructuredLogLoggingBridge(category: null));

      Logger('x').info('m');

      expect(entries.single.keys, isNot(contains('category')));
    });

    test('context adds fields, such as a request id from the zone', () {
      attached(StructuredLogLoggingBridge(
        context: (record) => {'request_id': record.zone?[#requestId]},
      ));

      runZoned(
        () => Logger('x').info('m'),
        zoneValues: {#requestId: 'r1'},
      );

      expect(entries.single, containsPair('request_id', 'r1'));
    });

    test('filter leaves the records it rejects out', () {
      attached(StructuredLogLoggingBridge(
        filter: (record) => record.loggerName != 'noisy',
      ));

      Logger('noisy').info('chatter');
      Logger('quiet').info('kept');

      expect(eventsOf(entries), ['kept']);
    });
  });

  group('never throws into the caller', () {
    test('a throwing filter costs the entry its type, not the call', () {
      final errors = uncaughtErrorsOf(() {
        attached(StructuredLogLoggingBridge(
          filter: (_) => throw const FormatException('secret=1'),
        ));
        Logger('x').info('m');
      });

      expect(errors, isEmpty);
      expect(entries.single, containsPair('bridge_failed', 'FormatException'));
      expect(jsonEncode(entries), isNot(contains('secret=1')));
    });

    test('a throwing levelOf falls back to the default mapping', () {
      final errors = uncaughtErrorsOf(() {
        attached(StructuredLogLoggingBridge(
          levelOf: (_) => throw StateError('levelOf'),
        ));
        Logger('x').severe('m');
      });

      expect(errors, isEmpty);
      expect(entries.single, containsPair('level', 'error'));
      expect(entries.single, containsPair('bridge_failed', 'StateError'));
    });

    test('a throwing context costs only its fields', () {
      final errors = uncaughtErrorsOf(() {
        attached(StructuredLogLoggingBridge(
          context: (_) => throw StateError('context'),
        ));
        Logger('x').info('m');
      });

      expect(errors, isEmpty);
      expect(entries.single, containsPair('event', 'm'));
      expect(entries.single, containsPair('bridge_failed', 'StateError'));
    });

    test('a failing sink does not reach the caller either', () {
      StructlogConfiguration.configure(
        sinks: [
          LogSink(
            name: 'broken',
            output: (_, __) => throw StateError('sink'),
          ),
        ],
      );
      final errors = uncaughtErrorsOf(() {
        attached();
        Logger('x').info('m');
      });

      expect(errors, isEmpty);
    });
  });

  group('recursion', () {
    // package:logging's stream refuses an event while it is firing one, so
    // the bridge cannot be re-entered: the sink's own call throws instead.
    // Pinned because the bridge relies on it rather than guarding itself.
    test('a sink that logs through package:logging gets a StateError', () {
      final received = <String>[];
      final thrown = <Object>[];
      StructlogConfiguration.configure(
        sinks: [
          LogSink(
            name: 'loops',
            output: (entry, _) {
              received.add(entry['event'] as String);
              try {
                Logger('sink').info('wrote');
              } catch (error) {
                thrown.add(error);
              }
            },
            minLevel: LogLevel.trace,
          ),
        ],
      );
      attached();

      Logger('x').info('m');

      expect(received, ['m']);
      expect(thrown, [isA<StateError>()]);
    });

    test('a record written after a delivery is over goes through', () async {
      StructlogConfiguration.configure(
        sinks: [
          LogSink(
            name: 'later',
            output: (entry, _) {
              entries.add(Map.of(entry));
              if (entry['event'] == 'first') {
                scheduleMicrotask(() => Logger('sink').info('second'));
              }
            },
            minLevel: LogLevel.trace,
          ),
        ],
      );
      attached();

      Logger('x').info('first');
      await Future<void>.delayed(Duration.zero);

      expect(eventsOf(entries), ['first', 'second']);
    });
  });

  group('attach and detach', () {
    test('attaching twice does not write twice', () {
      final bridge = attached();
      bridge.attach();

      Logger('x').info('m');

      expect(entries, hasLength(1));
      expect(bridge.isAttached, isTrue);
    });

    test('detach stops the entries, and attach starts them again', () {
      final bridge = attached();

      bridge.detach();
      Logger('x').info('dropped');
      bridge.attach();
      Logger('x').info('kept');

      expect(eventsOf(entries), ['kept']);
    });

    test('a non-root source bridges its own records', () {
      hierarchicalLoggingEnabled = true;
      final source = Logger('app');
      attached(StructuredLogLoggingBridge(source: source));

      Logger('app.db').info('child');
      Logger('other').info('elsewhere');

      expect(eventsOf(entries), ['child']);
      expect(entries.single, containsPair('logger', 'app.db'));
    });
  });

  group('configuration', () {
    test('a later configure() reaches an attached bridge', () {
      final old = <String>[];
      final current = <String>[];
      StructlogConfiguration.configure(
        sinks: [
          LogSink(name: 'old', output: (e, _) => old.add(e['event'])),
        ],
      );
      attached();
      StructlogConfiguration.configure(
        sinks: [
          LogSink(name: 'new', output: (e, _) => current.add(e['event'])),
        ],
      );

      Logger('x').info('m');

      expect(current, ['m']);
      expect(old, isEmpty);
    });

    test('every entry survives jsonEncode', () {
      attached();

      Logger('x').severe('m', StateError('e'), StackTrace.current);

      expect(() => jsonEncode(entries), returnsNormally);
    });
  });
}
