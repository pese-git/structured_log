import 'package:structured_log_server/src/ingest/ingest.dart';
import 'package:test/test.dart';

final _now = DateTime.utc(2026, 1, 1);

Map<String, Object?> validEntry({
  String event = 'e',
  String level = 'info',
  String? timestamp,
}) =>
    {
      'event': event,
      'level': level,
      'timestamp': timestamp ?? _now.toIso8601String()
    };

void main() {
  group('validation', () {
    test('a well-formed entry is accepted', () {
      final outcome = processIngestBatch(
        rawEntries: [validEntry()],
        maxEntries: null,
        maxBytes: null,
        currentEntryCount: 0,
        currentTotalBytes: 0,
        receivedAt: _now,
      );
      expect(outcome.accepted, hasLength(1));
      expect(outcome.rejected, isEmpty);
    });

    test('a non-object entry is rejected', () {
      final outcome = processIngestBatch(
        rawEntries: ['not an object'],
        maxEntries: null,
        maxBytes: null,
        currentEntryCount: 0,
        currentTotalBytes: 0,
        receivedAt: _now,
      );
      expect(outcome.rejected.single.error, 'validation_error');
      expect(outcome.rejected.single.index, 0);
    });

    test('a missing level is rejected', () {
      final entry = validEntry()..remove('level');
      final outcome = processIngestBatch(
        rawEntries: [entry],
        maxEntries: null,
        maxBytes: null,
        currentEntryCount: 0,
        currentTotalBytes: 0,
        receivedAt: _now,
      );
      expect(outcome.rejected.single.error, 'validation_error');
      expect(outcome.rejected.single.message, contains('level'));
    });

    test('an unrecognized level is rejected', () {
      final outcome = processIngestBatch(
        rawEntries: [validEntry(level: 'catastrophic')],
        maxEntries: null,
        maxBytes: null,
        currentEntryCount: 0,
        currentTotalBytes: 0,
        receivedAt: _now,
      );
      expect(outcome.rejected.single.error, 'validation_error');
    });

    test('trace is a recognized level', () {
      final outcome = processIngestBatch(
        rawEntries: [validEntry(level: 'trace')],
        maxEntries: null,
        maxBytes: null,
        currentEntryCount: 0,
        currentTotalBytes: 0,
        receivedAt: _now,
      );
      expect(outcome.accepted, hasLength(1));
    });

    test('a missing event is rejected', () {
      final entry = validEntry()..remove('event');
      final outcome = processIngestBatch(
        rawEntries: [entry],
        maxEntries: null,
        maxBytes: null,
        currentEntryCount: 0,
        currentTotalBytes: 0,
        receivedAt: _now,
      );
      expect(outcome.rejected.single.error, 'validation_error');
    });

    test('an unparsable timestamp is rejected', () {
      final outcome = processIngestBatch(
        rawEntries: [validEntry(timestamp: 'not-a-date')],
        maxEntries: null,
        maxBytes: null,
        currentEntryCount: 0,
        currentTotalBytes: 0,
        receivedAt: _now,
      );
      expect(outcome.rejected.single.error, 'validation_error');
    });

    test('a valid and an invalid entry in the same batch are both reported',
        () {
      final bad = validEntry()..remove('level');
      final outcome = processIngestBatch(
        rawEntries: [validEntry(), bad],
        maxEntries: null,
        maxBytes: null,
        currentEntryCount: 0,
        currentTotalBytes: 0,
        receivedAt: _now,
      );
      expect(outcome.accepted, hasLength(1));
      expect(outcome.rejected, hasLength(1));
      expect(outcome.rejected.single.index, 1);
    });
  });

  group('quota — max_entries', () {
    test('an entry within the limit is accepted', () {
      final outcome = processIngestBatch(
        rawEntries: [validEntry()],
        maxEntries: 1000,
        maxBytes: null,
        currentEntryCount: 999,
        currentTotalBytes: 0,
        receivedAt: _now,
      );
      expect(outcome.accepted, hasLength(1));
      expect(outcome.entryCountDelta, 1);
    });

    test('an entry that would exceed the limit is rejected with quota_exceeded',
        () {
      final outcome = processIngestBatch(
        rawEntries: [validEntry()],
        maxEntries: 1000,
        maxBytes: null,
        currentEntryCount: 1000,
        currentTotalBytes: 0,
        receivedAt: _now,
      );
      expect(outcome.accepted, isEmpty);
      expect(outcome.rejected.single.error, 'quota_exceeded');
      expect(outcome.entryCountDelta, 0);
    });

    test('entries within one batch are counted cumulatively', () {
      final outcome = processIngestBatch(
        rawEntries: [validEntry(), validEntry(), validEntry()],
        maxEntries: 2,
        maxBytes: null,
        currentEntryCount: 0,
        currentTotalBytes: 0,
        receivedAt: _now,
      );
      expect(outcome.accepted, hasLength(2));
      expect(outcome.rejected, hasLength(1));
      expect(outcome.rejected.single.index, 2);
    });
  });

  group('quota — max_bytes', () {
    test(
        'an entry that would exceed max_bytes is rejected without touching total_bytes',
        () {
      final outcome = processIngestBatch(
        rawEntries: [validEntry()],
        maxEntries: null,
        maxBytes: 1,
        currentEntryCount: 0,
        currentTotalBytes: 0,
        receivedAt: _now,
      );
      expect(outcome.accepted, isEmpty);
      expect(outcome.rejected.single.error, 'quota_exceeded');
      expect(outcome.bytesDelta, 0);
    });

    test('no max_bytes means no byte limit', () {
      final outcome = processIngestBatch(
        rawEntries: [validEntry()],
        maxEntries: null,
        maxBytes: null,
        currentEntryCount: 0,
        currentTotalBytes: 1 << 40,
        receivedAt: _now,
      );
      expect(outcome.accepted, hasLength(1));
    });
  });

  test('a custom context field is preserved in the stored contextJson', () {
    final entry = validEntry();
    entry['order_id'] = 'ord_42';
    final outcome = processIngestBatch(
      rawEntries: [entry],
      maxEntries: null,
      maxBytes: null,
      currentEntryCount: 0,
      currentTotalBytes: 0,
      receivedAt: _now,
    );
    final companion = outcome.accepted.single;
    expect(companion.contextJson.value, contains('ord_42'));
  });
}
