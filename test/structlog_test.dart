import 'dart:convert';
import 'dart:io';

import 'package:structured_log/structured_log.dart';
import 'package:test/test.dart';

void main() {
  group('BoundLogger', () {
    test('bind adds context to log entries', () {
      final log = getLogger().bind({'key': 'value'});
      expect(log, isA<BoundLogger>());
    });

    test('unbind removes keys from context', () {
      final log = getLogger().bind({'key1': 'a', 'key2': 'b'});
      final unbound = log.unbind(['key1']);
      expect(unbound, isA<BoundLogger>());
    });

    test('log levels work correctly', () {
      final log = getLogger();
      log.trace('test');
      log.debug('test');
      log.info('test');
      log.warning('test');
      log.error('test');
      log.critical('test');
    });
  });

  group('Configuration', () {
    tearDown(() {
      StructlogConfiguration.reset();
    });

    test('configure updates settings', () {
      StructlogConfiguration.configure(
        initialContext: {'app': 'test'},
      );
      expect(StructlogConfiguration.current.initialContext['app'], 'test');
    });

    test('reset restores defaults', () {
      StructlogConfiguration.configure(
        initialContext: {'app': 'test'},
      );
      StructlogConfiguration.reset();
      expect(StructlogConfiguration.current.initialContext, isEmpty);
    });
  });

  group('Processors', () {
    test('dropNullValues removes null entries', () {
      final entry = {'a': 1, 'b': null, 'c': 'test'};
      final result = dropNullValues(entry);
      expect(result, isNotNull);
      expect(result!.containsKey('b'), isFalse);
    });
  });

  group('Correlation', () {
    tearDown(() {
      StructlogConfiguration.reset();
    });

    test('all 6 fields serialize under fixed snake_case keys', () {
      Map<String, dynamic>? captured;
      StructlogConfiguration.configure(
        output: (entry, level) => captured = entry,
      );

      getLogger()
          .withCorrelation(
            sessionId: 's-14',
            requestId: 'r-42',
            connectionGeneration: 8,
            toolCallId: 'tc-3',
            messageId: 'm-1',
            operationId: 'op-9',
          )
          .info('event');

      expect(captured, isNotNull);
      expect(captured!['session_id'], 's-14');
      expect(captured!['request_id'], 'r-42');
      expect(captured!['connection_generation'], 8);
      expect(captured!['tool_call_id'], 'tc-3');
      expect(captured!['message_id'], 'm-1');
      expect(captured!['operation_id'], 'op-9');
    });

    test('child logger inherits and can override without mutating parent', () {
      final captures = <Map<String, dynamic>>[];
      StructlogConfiguration.configure(
        output: (entry, level) => captures.add(entry),
      );

      final parent =
          getLogger().withCorrelation(sessionId: 's-14', requestId: 'r-42');
      final child = parent.withCorrelation(toolCallId: 'tc-3');

      parent.info('parent_event');
      child.info('child_event');

      final parentEntry =
          captures.firstWhere((e) => e['event'] == 'parent_event');
      final childEntry =
          captures.firstWhere((e) => e['event'] == 'child_event');

      expect(parentEntry.containsKey('tool_call_id'), isFalse);
      expect(childEntry['session_id'], 's-14');
      expect(childEntry['request_id'], 'r-42');
      expect(childEntry['tool_call_id'], 'tc-3');
    });

    test('typed correlation field wins over same-named map context key', () {
      Map<String, dynamic>? captured;
      StructlogConfiguration.configure(
        output: (entry, level) => captured = entry,
      );

      getLogger().withCorrelation(sessionId: 'typed').info(
        'event',
        context: {'session_id': 'from_map'},
      );

      expect(captured!['session_id'], 'typed');
    });
  });

  group('Sinks', () {
    tearDown(() {
      StructlogConfiguration.reset();
    });

    test('one entry passing multiple sinks is delivered to all of them', () {
      final a = <Map<String, dynamic>>[];
      final b = <Map<String, dynamic>>[];
      StructlogConfiguration.configure(sinks: [
        LogSink(name: 'a', output: (entry, level) => a.add(entry)),
        LogSink(name: 'b', output: (entry, level) => b.add(entry)),
      ]);

      getLogger().info('event');

      expect(a, hasLength(1));
      expect(b, hasLength(1));
    });

    test('minLevel filters out lower-level entries per sink', () {
      final debugSink = <Map<String, dynamic>>[];
      final errorSink = <Map<String, dynamic>>[];
      StructlogConfiguration.configure(sinks: [
        LogSink(name: 'debug', output: (e, l) => debugSink.add(e)),
        LogSink(
          name: 'error',
          output: (e, l) => errorSink.add(e),
          minLevel: LogLevel.error,
        ),
      ]);

      final log = getLogger();
      log.info('low');
      log.error('high');

      expect(debugSink, hasLength(2));
      expect(errorSink, hasLength(1));
      expect(errorSink.single['event'], 'high');
    });

    test(
        "trace is below a sink's default minLevel (debug) and is filtered "
        'out unless a sink explicitly opts in', () {
      final defaultSink = <Map<String, dynamic>>[];
      final traceSink = <Map<String, dynamic>>[];
      StructlogConfiguration.configure(sinks: [
        LogSink(name: 'default', output: (e, l) => defaultSink.add(e)),
        LogSink(
          name: 'trace',
          output: (e, l) => traceSink.add(e),
          minLevel: LogLevel.trace,
        ),
      ]);

      final log = getLogger();
      log.trace('raw_frame');
      log.debug('normal');

      expect(defaultSink, hasLength(1));
      expect(defaultSink.single['event'], 'normal');
      expect(traceSink, hasLength(2));
    });

    test('categories filter routes entries by the category context key', () {
      final protocolSink = <Map<String, dynamic>>[];
      final appSink = <Map<String, dynamic>>[];
      StructlogConfiguration.configure(sinks: [
        LogSink(
          name: 'protocol',
          output: (e, l) => protocolSink.add(e),
          categories: {'protocol'},
        ),
        LogSink(name: 'app', output: (e, l) => appSink.add(e)),
      ]);

      final log = getLogger();
      log.info('app_event');
      log.info('protocol_event', context: {'category': 'protocol'});

      expect(appSink, hasLength(2));
      expect(protocolSink, hasLength(1));
      expect(protocolSink.single['event'], 'protocol_event');
    });

    test('setSinkEnabled toggles a sink in the running configuration', () {
      final captured = <Map<String, dynamic>>[];
      StructlogConfiguration.configure(sinks: [
        LogSink(name: 'toggle', output: (e, l) => captured.add(e)),
      ]);

      final log = getLogger();
      StructlogConfiguration.setSinkEnabled('toggle', enabled: false);
      log.info('while_disabled');
      expect(captured, isEmpty);

      StructlogConfiguration.setSinkEnabled('toggle', enabled: true);
      log.info('while_enabled');
      expect(captured, hasLength(1));
    });

    test('a throwing sink does not block delivery to other sinks', () {
      final good = <Map<String, dynamic>>[];
      StructlogConfiguration.configure(sinks: [
        LogSink(
          name: 'bad',
          output: (e, l) => throw StateError('boom'),
        ),
        LogSink(name: 'good', output: (e, l) => good.add(e)),
      ]);

      expect(() => getLogger().info('event'), returnsNormally);
      expect(good, hasLength(1));
    });

    test('legacy single-output configure() still works as one default sink',
        () {
      final captured = <Map<String, dynamic>>[];
      StructlogConfiguration.configure(
        output: (entry, level) => captured.add(entry),
      );

      getLogger().info('event');

      expect(captured, hasLength(1));
    });
  });

  group('Async outputs', () {
    tearDown(() {
      StructlogConfiguration.reset();
    });

    test('writes entries in order and flushed completes once all are written',
        () async {
      final dir = Directory.systemTemp.createTempSync('structured_log_test_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/app.log';
      final asyncOutput = AsyncFileOutput(path);
      StructlogConfiguration.configure(output: asyncOutput);

      final log = getLogger();
      for (var i = 0; i < 5; i++) {
        log.info('event', context: {'i': i});
      }
      await asyncOutput.flushed;

      final lines = File(path).readAsLinesSync();
      expect(lines, hasLength(5));
      for (var i = 0; i < 5; i++) {
        expect(jsonDecode(lines[i])['i'], i);
      }
    });

    test('a failing write does not throw and the queue still resolves',
        () async {
      final dir = Directory.systemTemp.createTempSync('structured_log_test_');
      addTearDown(() => dir.deleteSync(recursive: true));
      // A path that is itself an existing directory can never be opened as
      // a file, so every write to it is guaranteed to fail.
      final badPath = '${dir.path}/not_a_file';
      Directory(badPath).createSync();
      final asyncOutput = AsyncFileOutput(badPath);
      StructlogConfiguration.configure(output: asyncOutput);

      final log = getLogger();
      log.info('one');
      log.info('two');

      await expectLater(asyncOutput.flushed, completes);
    });

    test('rotates when exceeding maxSizeBytes', () async {
      final dir = Directory.systemTemp.createTempSync('structured_log_test_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/rotating.log';
      final asyncOutput = AsyncRotatingFileOutput(path, maxSizeBytes: 100);
      StructlogConfiguration.configure(output: asyncOutput);

      final log = getLogger();
      for (var i = 0; i < 50; i++) {
        log.info('iteration', context: {'i': i});
      }
      await asyncOutput.flushed;

      expect(File('$path.0').existsSync(), isTrue);
    });
  });
}
