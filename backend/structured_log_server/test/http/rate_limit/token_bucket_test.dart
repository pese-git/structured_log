import 'package:structured_log_server/src/http/rate_limit/token_bucket.dart';
import 'package:test/test.dart';

final _t0 = DateTime.utc(2026, 1, 1);

TokenBucket bucket({int capacity = 3, int refillPerMinute = 60}) => TokenBucket(
      capacity: capacity,
      refillPerMinute: refillPerMinute,
      now: _t0,
    );

void main() {
  // Time is a parameter here rather than read from the clock, which is the
  // only reason recovery can be asserted at all — otherwise every one of
  // these would have to wait out a real minute (`tasks.md` 28.9).
  group('consumption', () {
    test('starts full and spends one token per call', () {
      final b = bucket(capacity: 3);
      expect(b.tokensAt(_t0), 3);

      expect(b.tryConsume(_t0), isTrue);
      expect(b.tryConsume(_t0), isTrue);
      expect(b.tryConsume(_t0), isTrue);
      expect(b.tryConsume(_t0), isFalse, reason: 'exhausted');
      expect(b.tokensAt(_t0), lessThan(1));
    });

    test('an exhausted bucket stays exhausted without time passing', () {
      final b = bucket(capacity: 1);
      expect(b.tryConsume(_t0), isTrue);
      for (var i = 0; i < 5; i++) {
        expect(b.tryConsume(_t0), isFalse);
      }
    });
  });

  group('refill', () {
    test('accrues continuously rather than in whole-minute lumps', () {
      // 60/minute is one per second: after half a second there should be
      // half a token, not zero and not one.
      final b = bucket(capacity: 10, refillPerMinute: 60);
      for (var i = 0; i < 10; i++) {
        b.tryConsume(_t0);
      }

      expect(b.tokensAt(_t0.add(const Duration(milliseconds: 500))),
          closeTo(0.5, 0.01));
      expect(b.tokensAt(_t0.add(const Duration(seconds: 2))), closeTo(2, 0.01));
    });

    test('recovers on its own, with no administrator involved', () {
      final b = bucket(capacity: 2, refillPerMinute: 60);
      expect(b.tryConsume(_t0), isTrue);
      expect(b.tryConsume(_t0), isTrue);
      expect(b.tryConsume(_t0), isFalse);

      expect(b.tryConsume(_t0.add(const Duration(seconds: 1))), isTrue);
    });

    test('never exceeds capacity however long it idles', () {
      final b = bucket(capacity: 3, refillPerMinute: 60);
      b.tryConsume(_t0);
      expect(b.tokensAt(_t0.add(const Duration(days: 7))), 3);
    });

    test('a clock that moved backwards neither drains nor fills', () {
      // Not hypothetical on a server: NTP steps, and a bucket that treated
      // negative elapsed time as a refill would hand out free tokens.
      final b = bucket(capacity: 3, refillPerMinute: 60);
      b.tryConsume(_t0);
      b.tryConsume(_t0);

      final before = _t0.subtract(const Duration(hours: 1));
      expect(b.tokensAt(before), closeTo(1, 0.01));
      expect(b.tryConsume(before), isTrue);
    });
  });

  group('restore', () {
    test('refills to capacity regardless of how empty it was', () {
      final b = bucket(capacity: 5, refillPerMinute: 1);
      for (var i = 0; i < 5; i++) {
        b.tryConsume(_t0);
      }
      expect(b.tryConsume(_t0), isFalse);

      b.restore(_t0);
      expect(b.tokensAt(_t0), 5);
      expect(b.tryConsume(_t0), isTrue);
    });
  });

  group('timeUntilNextToken', () {
    test('is zero while tokens remain', () {
      expect(bucket().timeUntilNextToken(_t0), Duration.zero);
    });

    test('reports the wait for the next token once exhausted', () {
      final b = bucket(capacity: 1, refillPerMinute: 60);
      b.tryConsume(_t0);

      expect(b.timeUntilNextToken(_t0), const Duration(seconds: 1));
      expect(
        b.timeUntilNextToken(_t0.add(const Duration(milliseconds: 750))),
        const Duration(milliseconds: 250),
      );
    });

    test('a slower refill means a longer wait', () {
      final b = bucket(capacity: 1, refillPerMinute: 6);
      b.tryConsume(_t0);
      expect(b.timeUntilNextToken(_t0), const Duration(seconds: 10));
    });

    test('the reported wait is actually enough', () {
      final b = bucket(capacity: 2, refillPerMinute: 7);
      b.tryConsume(_t0);
      b.tryConsume(_t0);

      final wait = b.timeUntilNextToken(_t0);
      expect(b.tryConsume(_t0.add(wait)), isTrue,
          reason: 'Retry-After must not point at a moment still too early');
    });
  });

  group('construction', () {
    test('rejects a capacity below one', () {
      expect(
        () => TokenBucket(capacity: 0, refillPerMinute: 1, now: _t0),
        throwsArgumentError,
      );
    });

    test('rejects a refill rate that would never recover', () {
      expect(
        () => TokenBucket(capacity: 1, refillPerMinute: 0, now: _t0),
        throwsArgumentError,
      );
    });
  });
}
