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
}
