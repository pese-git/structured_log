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
}
