import 'package:structured_log_server/src/live/subscription_limit.dart';
import 'package:test/test.dart';

void main() {
  group('per-account ceiling', () {
    test('holds the account at its limit', () {
      final limiter = SubscriptionLimiter(perUser: 2, total: 100);

      expect(limiter.tryAcquire(1), isNotNull);
      expect(limiter.tryAcquire(1), isNotNull);
      expect(limiter.tryAcquire(1), isNull);
    });

    test('one account filling up does not touch another', () {
      final limiter = SubscriptionLimiter(perUser: 1, total: 100);

      expect(limiter.tryAcquire(1), isNotNull);
      expect(limiter.tryAcquire(1), isNull);
      expect(
        limiter.tryAcquire(2),
        isNotNull,
        reason: 'the per-account ceiling is per account, or it is a global one',
      );
    });

    test('releasing frees the slot for the same account', () {
      final limiter = SubscriptionLimiter(perUser: 1, total: 100);

      final slot = limiter.tryAcquire(1)!;
      expect(limiter.tryAcquire(1), isNull);
      slot.release();
      expect(limiter.tryAcquire(1), isNotNull);
    });
  });

  group('process ceiling', () {
    test('holds every account together at the total', () {
      final limiter = SubscriptionLimiter(perUser: 100, total: 2);

      expect(limiter.tryAcquire(1), isNotNull);
      expect(limiter.tryAcquire(2), isNotNull);
      expect(
        limiter.tryAcquire(3),
        isNull,
        reason:
            'the per-account ceiling alone protects nothing against many '
            'accounts, which is the case a compromised deployment is in',
      );
    });

    test('a refusal by the total does not consume the account', () {
      final limiter = SubscriptionLimiter(perUser: 5, total: 1);

      limiter.tryAcquire(1);
      expect(limiter.tryAcquire(2), isNull);
      // Account 2 was refused, so nothing of its own was spent: once the
      // process has room again it may take a slot.
      limiter.tryAcquire(1);
      expect(limiter.held(2), 0);
    });
  });

  group('releasing is idempotent, which is the whole risk here', () {
    // The route reaches its one teardown twice — `end()` calls it, and
    // closing the body calls it again through the controller's `onCancel`.
    // A plain decrement would count a single subscription out twice, the
    // counter would drift below the truth, and the ceiling would stop being
    // one.
    test('a second release changes nothing', () {
      final limiter = SubscriptionLimiter(perUser: 2, total: 100);

      final slot = limiter.tryAcquire(1)!;
      limiter.tryAcquire(1);
      slot.release();
      slot.release();
      slot.release();

      expect(limiter.held(1), 1, reason: 'one slot is still out');
      expect(limiter.openTotal, 1);
    });

    test('the account is forgotten once it holds nothing', () {
      final limiter = SubscriptionLimiter(perUser: 2, total: 100);

      limiter.tryAcquire(7)!.release();

      expect(
        limiter.trackedAccounts,
        0,
        reason:
            'a counter kept per account id is a map an anonymous flood can '
            'grow without bound unless an empty entry goes away',
      );
    });
  });

  group('a ceiling of zero is no ceiling', () {
    test('per-account', () {
      final limiter = SubscriptionLimiter(perUser: 0, total: 100);
      for (var i = 0; i < 50; i++) {
        expect(limiter.tryAcquire(1), isNotNull);
      }
    });

    test('process-wide', () {
      final limiter = SubscriptionLimiter(perUser: 100, total: 0);
      for (var i = 0; i < 50; i++) {
        expect(limiter.tryAcquire(i), isNotNull);
      }
    });
  });
}
