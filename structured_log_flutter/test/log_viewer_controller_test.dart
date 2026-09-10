import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart';

void main() {
  group('LogViewerController', () {
    late LogBuffer buffer;
    late LogViewerController controller;

    setUp(() {
      buffer = LogBuffer();
      controller = LogViewerController(buffer);
    });

    tearDown(() => controller.dispose());

    test('starts unfiltered and unpaused', () {
      expect(controller.levelFilter, isNull);
      expect(controller.categoryFilter, isNull);
      expect(controller.searchQuery, isEmpty);
      expect(controller.paused, isFalse);
    });

    test('reflects new entries captured into the buffer', () {
      buffer.capture({'event': 'a', 'level': 'info'}, LogLevel.info);

      expect(controller.visibleEntries, hasLength(1));
    });

    test('levelFilter hides entries below the threshold', () {
      buffer.capture({'event': 'a', 'level': 'info'}, LogLevel.info);
      buffer.capture({'event': 'b', 'level': 'error'}, LogLevel.error);

      controller.levelFilter = LogLevel.warning;

      expect(controller.visibleEntries.map((e) => e['event']), ['b']);
    });

    test('categoryFilter keeps only matching entries', () {
      buffer.capture(
        {'event': 'a', 'level': 'info', 'category': 'network'},
        LogLevel.info,
      );
      buffer.capture(
        {'event': 'b', 'level': 'info', 'category': 'database'},
        LogLevel.info,
      );

      controller.categoryFilter = 'network';

      expect(controller.visibleEntries.map((e) => e['event']), ['a']);
    });

    test('searchQuery matches a substring of event, case-insensitively', () {
      buffer.capture(
          {'event': 'payment_failed', 'level': 'error'}, LogLevel.error);
      buffer.capture({'event': 'user_login', 'level': 'info'}, LogLevel.info);

      controller.searchQuery = 'PAYMENT';

      expect(
          controller.visibleEntries.map((e) => e['event']), ['payment_failed']);
    });

    test('searchQuery matches a substring of a context value', () {
      buffer.capture(
        {'event': 'slow_query', 'level': 'warning', 'query': 'SELECT *'},
        LogLevel.warning,
      );
      buffer.capture({'event': 'user_login', 'level': 'info'}, LogLevel.info);

      controller.searchQuery = 'select';

      expect(controller.visibleEntries.map((e) => e['event']), ['slow_query']);
    });

    test('paused freezes visibleEntries against later captures', () {
      buffer.capture({'event': 'a', 'level': 'info'}, LogLevel.info);
      controller.paused = true;

      buffer.capture({'event': 'b', 'level': 'info'}, LogLevel.info);

      expect(controller.visibleEntries.map((e) => e['event']), ['a']);
    });

    test('resuming after pause picks up entries captured while paused', () {
      controller.paused = true;
      buffer.capture({'event': 'a', 'level': 'info'}, LogLevel.info);
      controller.paused = false;

      expect(controller.visibleEntries.map((e) => e['event']), ['a']);
    });

    test('clear empties the buffer and visibleEntries', () {
      buffer.capture({'event': 'a', 'level': 'info'}, LogLevel.info);

      controller.clear();

      expect(controller.visibleEntries, isEmpty);
      expect(buffer.entries.value, isEmpty);
    });

    test('clear notifies listeners', () {
      var notified = false;
      controller.addListener(() => notified = true);

      controller.clear();

      expect(notified, isTrue);
    });

    test('notifies listeners when a new entry is captured', () {
      var notified = false;
      controller.addListener(() => notified = true);

      buffer.capture({'event': 'a', 'level': 'info'}, LogLevel.info);

      expect(notified, isTrue);
    });

    test('does not notify listeners for captures while paused', () {
      controller.paused = true;
      var notified = false;
      controller.addListener(() => notified = true);

      buffer.capture({'event': 'a', 'level': 'info'}, LogLevel.info);

      expect(notified, isFalse);
    });
  });
}
