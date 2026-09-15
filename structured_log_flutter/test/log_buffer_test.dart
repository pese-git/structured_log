import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart';

void main() {
  group('LogBuffer', () {
    test('capture appends entries, oldest first', () {
      final buffer = LogBuffer();

      buffer.capture({'event': 'a'}, LogLevel.info);
      buffer.capture({'event': 'b'}, LogLevel.info);

      expect(buffer.entries.value.map((e) => e['event']), ['a', 'b']);
    });

    test('evicts the oldest entry once capacity is exceeded', () {
      final buffer = LogBuffer(capacity: 2);

      buffer.capture({'event': 'a'}, LogLevel.info);
      buffer.capture({'event': 'b'}, LogLevel.info);
      buffer.capture({'event': 'c'}, LogLevel.info);

      expect(buffer.entries.value.map((e) => e['event']), ['b', 'c']);
    });

    test('entries ValueListenable notifies on capture', () {
      final buffer = LogBuffer();
      var notifications = 0;
      buffer.entries.addListener(() => notifications++);

      buffer.capture({'event': 'a'}, LogLevel.info);

      expect(notifications, 1);
    });

    test('capture plugs directly into a LogSink as its output', () {
      final buffer = LogBuffer();
      StructlogConfiguration.configure(
        sinks: [LogSink(name: 'viewer', output: buffer.capture)],
      );
      addTearDown(StructlogConfiguration.reset);

      getLogger().info('user_login', context: {'user_id': 42});

      expect(buffer.entries.value, hasLength(1));
      expect(buffer.entries.value.single['event'], 'user_login');
      expect(buffer.entries.value.single['user_id'], 42);
    });

    test('clear empties the buffer and notifies listeners', () {
      final buffer = LogBuffer()..capture({'event': 'a'}, LogLevel.info);
      var notified = false;
      buffer.entries.addListener(() => notified = true);

      buffer.clear();

      expect(buffer.entries.value, isEmpty);
      expect(notified, isTrue);
    });
  });
}
