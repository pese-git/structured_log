import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart';

void main() {
  group('LogBuffer notifies once per burst', () {
    test('a hundred captures in one go make one notification', () async {
      final buffer = LogBuffer(capacity: 1000);
      var notifications = 0;
      buffer.entries.addListener(() => notifications++);

      for (var i = 0; i < 100; i++) {
        buffer.capture({'event': 'e$i'}, LogLevel.info);
      }
      expect(notifications, 0, reason: 'the notification waits for the burst');

      await pumpEventQueue();

      expect(notifications, 1);
      expect(buffer.entries.value, hasLength(100));
      expect(buffer.entries.value.first['event'], 'e0');
      expect(buffer.entries.value.last['event'], 'e99');
    });

    test('a burst schedules one microtask, not one per entry', () {
      final buffer = LogBuffer(capacity: 1000);
      var scheduled = 0;

      runZoned(
        () {
          for (var i = 0; i < 100; i++) {
            buffer.capture({'event': 'e$i'}, LogLevel.info);
          }
        },
        zoneSpecification: ZoneSpecification(
          scheduleMicrotask: (self, parent, zone, callback) {
            scheduled++;
            parent.scheduleMicrotask(zone, callback);
          },
        ),
      );

      expect(scheduled, 1);
    });

    test('the value is current even before the notification', () {
      final buffer = LogBuffer();

      buffer.capture({'event': 'a'}, LogLevel.info);

      expect(buffer.entries.value.single['event'], 'a');
    });

    test('a published list never changes afterwards', () async {
      final buffer = LogBuffer(capacity: 2)
        ..capture({'event': 'a'}, LogLevel.info);
      final first = buffer.entries.value;

      buffer
        ..capture({'event': 'b'}, LogLevel.info)
        ..capture({'event': 'c'}, LogLevel.info);
      await pumpEventQueue();

      expect(first.map((e) => e['event']), ['a']);
      expect(() => first.add({}), throwsUnsupportedError);
      expect(buffer.entries.value.map((e) => e['event']), ['b', 'c']);
    });

    test('reading twice without a change gives the same list', () {
      final buffer = LogBuffer()..capture({'event': 'a'}, LogLevel.info);

      expect(buffer.entries.value, same(buffer.entries.value));
    });

    test('clear() notifies at once, and a pending burst adds no more',
        () async {
      final buffer = LogBuffer();
      var notifications = 0;
      buffer.entries.addListener(() => notifications++);

      buffer
        ..capture({'event': 'a'}, LogLevel.info)
        ..clear();
      expect(notifications, 1);
      expect(buffer.entries.value, isEmpty);

      await pumpEventQueue();
      expect(notifications, 1);
    });

    test('capacity holds across a burst', () async {
      final buffer = LogBuffer(capacity: 3);

      for (var i = 0; i < 10; i++) {
        buffer.capture({'event': 'e$i'}, LogLevel.info);
      }
      await pumpEventQueue();

      expect(buffer.entries.value.map((e) => e['event']), ['e7', 'e8', 'e9']);
    });
  });

  group('debugPrintOutput', () {
    late List<String?> printed;
    late DebugPrintCallback original;

    setUp(() {
      printed = [];
      original = debugPrint;
      debugPrint = (message, {wrapWidth}) => printed.add(message);
    });
    tearDown(() => debugPrint = original);

    test('writes one line: time, level, event, then the rest', () {
      final at = DateTime.utc(2026, 10, 2, 9, 30, 15, 250);

      debugPrintOutput({
        'event': 'login',
        'level': 'info',
        'timestamp': at.toIso8601String(),
        'user': 'u',
        'attempt': 2,
      }, LogLevel.info);

      final local = at.toLocal();
      String two(int n) => n.toString().padLeft(2, '0');
      final time = '${two(local.hour)}:${two(local.minute)}:'
          '${two(local.second)}.${local.millisecond.toString().padLeft(3, '0')}';
      expect(printed, ['$time INFO login user="u" attempt=2']);
    });

    test('no newline and no ANSI escape, whatever the values hold', () {
      debugPrintOutput({
        'event': 'line\nbreak',
        'message': 'a\nb\x1B[31m',
      }, LogLevel.error);

      expect(printed.single, isNot(contains('\n')));
      expect(printed.single, isNot(contains('\x1B')));
      expect(printed.single, r'ERROR "line\nbreak" message="a\nb\u001b[31m"');
    });

    test('an entry without a usable timestamp or event still prints', () {
      debugPrintOutput({'timestamp': 'not a time', 'n': 1}, LogLevel.debug);

      expect(printed, ['DEBUG n=1']);
    });
  });
}
