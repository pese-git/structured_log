import 'package:structured_log_server/src/http/rate_limit/bucket_store.dart';
import 'package:test/test.dart';

void main() {
  late DateTime now;
  DateTime clock() => now;

  BucketStore store({
    int capacity = 3,
    int refillPerMinute = 60,
    int maxKeys = 100,
    Duration sweepInterval = const Duration(minutes: 1),
  }) => BucketStore(
    capacity: capacity,
    refillPerMinute: refillPerMinute,
    maxKeys: maxKeys,
    clock: clock,
    sweepInterval: sweepInterval,
  );

  setUp(() => now = DateTime.utc(2026, 1, 1));

  group('identity', () {
    test('the same key gets the same bucket', () {
      final s = store();
      s['a'].tryConsume(now);

      expect(s['a'].tokensAt(now), 2, reason: 'not a fresh bucket');
    });

    test('different keys are independent', () {
      final s = store(capacity: 1);
      expect(s['a'].tryConsume(now), isTrue);

      expect(
        s['b'].tryConsume(now),
        isTrue,
        reason: "one key's exhaustion must not throttle another",
      );
    });

    test('a new key starts full', () {
      final s = store(capacity: 3);
      expect(s['fresh'].tokensAt(now), 3);
    });
  });

  group('bounded memory', () {
    test('never holds more than maxKeys buckets', () {
      final s = store(maxKeys: 5, sweepInterval: const Duration(days: 1));
      for (var i = 0; i < 100; i++) {
        s['key-$i'].tryConsume(now);
      }

      expect(s.length, lessThanOrEqualTo(5));
    });

    test('evicts the least recently used, not the oldest created', () {
      final s = store(maxKeys: 2, sweepInterval: const Duration(days: 1));
      s['a'].tryConsume(now);
      s['b'].tryConsume(now);
      // Touching 'a' should make 'b' the eviction candidate.
      s['a'].tryConsume(now);
      s['c'].tryConsume(now);

      expect(s.length, 2);
      expect(
        s['a'].tokensAt(now),
        lessThan(3),
        reason: 'a was kept, so it remembers its spent tokens',
      );
      expect(s['b'].tokensAt(now), 3, reason: 'b was evicted and is fresh');
    });

    test('eviction forgives rather than punishes', () {
      // Worth stating explicitly: overflowing the store can only ever let a
      // throttled key through early, never throttle an innocent one.
      final s = store(
        capacity: 1,
        maxKeys: 1,
        sweepInterval: const Duration(days: 1),
      );
      expect(s['victim'].tryConsume(now), isTrue);
      expect(s['victim'].tryConsume(now), isFalse);

      s['attacker'].tryConsume(now);

      expect(
        s['victim'].tryConsume(now),
        isTrue,
        reason: 'forgotten, not denied',
      );
    });
  });

  group('sweep', () {
    test('drops buckets that have refilled to full', () {
      final s = store(
        capacity: 2,
        refillPerMinute: 60,
        sweepInterval: const Duration(seconds: 30),
      );
      s['a'].tryConsume(now);
      s['b'].tryConsume(now);
      expect(s.length, 2);

      // Both refill long before the sweep is due, so by the time it runs
      // they carry no information and should be gone.
      now = now.add(const Duration(minutes: 5));
      s['trigger'];

      expect(s.length, 1, reason: 'only the key that triggered the sweep');
    });

    test('keeps buckets still short of full', () {
      final s = store(
        capacity: 10,
        refillPerMinute: 1,
        sweepInterval: const Duration(seconds: 1),
      );
      for (var i = 0; i < 10; i++) {
        s['busy'].tryConsume(now);
      }

      now = now.add(const Duration(seconds: 30));
      s['trigger'];

      expect(s.length, 2, reason: 'busy is not full yet and must be kept');
      expect(s['busy'].tokensAt(now), lessThan(10));
    });

    test('does not run more often than its interval', () {
      final s = store(capacity: 2, sweepInterval: const Duration(minutes: 10));
      s['a'].tryConsume(now);

      now = now.add(const Duration(minutes: 1));
      s['b'];

      expect(s.length, 2, reason: 'a refilled, but the sweep is not due yet');
    });
  });

  test('rejects a maxKeys below one', () {
    expect(
      () => BucketStore(
        capacity: 1,
        refillPerMinute: 1,
        maxKeys: 0,
        clock: clock,
      ),
      throwsArgumentError,
    );
  });
}
