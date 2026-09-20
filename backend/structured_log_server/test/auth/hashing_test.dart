import 'dart:async';

import 'package:structured_log_server/src/auth/hash_worker_pool.dart';
import 'package:structured_log_server/src/errors.dart';
import 'package:structured_log_server/src/auth/hashing.dart';
import 'package:test/test.dart';

void main() {
  group('hashPassword/verifyPassword', () {
    test('the hash is not the plaintext password', () {
      final hash = hashPassword('correct horse battery staple');
      expect(hash, isNot('correct horse battery staple'));
    });

    test('verifyPassword accepts the original password', () {
      final hash = hashPassword('s3cret');
      expect(verifyPassword('s3cret', hash), isTrue);
    });

    test('verifyPassword rejects a wrong password', () {
      final hash = hashPassword('s3cret');
      expect(verifyPassword('wrong', hash), isFalse);
    });
  });

  group('generateRandomToken', () {
    test('produces different values on each call', () {
      final a = generateRandomToken();
      final b = generateRandomToken();
      expect(a, isNot(b));
    });

    test('is URL-safe (no +, /, or padding)', () {
      final token = generateRandomToken();
      expect(token, isNot(contains('+')));
      expect(token, isNot(contains('/')));
      expect(token, isNot(contains('=')));
    });
  });

  group('hashToken', () {
    test('is deterministic for the same input', () {
      expect(hashToken('abc'), hashToken('abc'));
    });

    test('does not return the plaintext token', () {
      expect(hashToken('my-secret-key'), isNot('my-secret-key'));
    });

    test('different inputs hash to different values', () {
      expect(hashToken('a'), isNot(hashToken('b')));
    });
  });

  group('generateProjectSecretKey', () {
    test('carries the scheme prefix', () {
      expect(generateProjectSecretKey(), startsWith(projectSecretKeyPrefix));
    });

    test('cannot be confused with a JWT, which always starts with eyJ', () {
      expect(generateProjectSecretKey(), isNot(startsWith('eyJ')));
    });

    test('is unique per call', () {
      expect(generateProjectSecretKey(), isNot(generateProjectSecretKey()));
    });

    test('hashes as a whole, prefix included', () {
      final key = generateProjectSecretKey();
      final withoutPrefix = key.substring(projectSecretKeyPrefix.length);
      expect(hashToken(key), isNot(hashToken(withoutPrefix)));
    });

    test('leaves bare generateRandomToken unprefixed (refresh tokens)', () {
      expect(
        generateRandomToken(),
        isNot(startsWith(projectSecretKeyPrefix)),
      );
    });
  });

  group('async hashing', () {
    test('round-trips and agrees with the synchronous pair', () async {
      final hash = await hashPasswordAsync('s3cret');
      expect(await verifyPasswordAsync('s3cret', hash), isTrue);
      expect(await verifyPasswordAsync('wrong', hash), isFalse);
      expect(verifyPassword('s3cret', hash), isTrue);
      expect(
          await verifyPasswordAsync('s3cret', hashPassword('s3cret')), isTrue);
    });

    test('does not stall the event loop while it computes', () async {
      final hash = hashPassword('s3cret');
      var last = Stopwatch()..start();
      var worst = 0;
      final ticker =
          Stream.periodic(const Duration(milliseconds: 2)).listen((_) {
        if (last.elapsedMilliseconds > worst) worst = last.elapsedMilliseconds;
        last = Stopwatch()..start();
      });
      await verifyPasswordAsync('wrong', hash);
      await verifyPasswordAsync('wrong', hash);
      // Let the loop turn once more before looking: work done on the loop
      // itself finishes in microtasks, and the tick that would record the
      // stall is still waiting for its turn.
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await ticker.cancel();
      // A bcrypt check on the loop itself is one uninterrupted gap of its full
      // cost, ~130 ms here; 80 leaves room for a loaded CI machine.
      expect(worst, lessThan(80));
    });

    test('the dummy hash is a valid bcrypt hash nobody can guess', () async {
      final dummy = await dummyPasswordHash;
      expect(dummy, startsWith(r'$2'));
      expect(await verifyPasswordAsync('anything', dummy), isFalse);
    });
  });

  group('requireAcceptablePassword', () {
    Matcher rejectedAs(String reason, {String field = 'password'}) => throwsA(
          isA<ApiError>()
              .having((e) => e.statusCode, 'statusCode', 400)
              .having((e) => e.details?['reason'], 'reason', reason)
              .having((e) => e.details?['field'], 'field', field),
        );

    test('accepts the shortest and the longest allowed', () {
      requireAcceptablePassword('x' * minPasswordLength);
      requireAcceptablePassword('x' * maxPasswordBytes);
    });

    test('a password below the minimum is too_short and names the minimum', () {
      expect(
        () => requireAcceptablePassword('x' * (minPasswordLength - 1)),
        rejectedAs('too_short'),
      );
      expect(
        () => requireAcceptablePassword(''),
        rejectedAs('too_short'),
      );
      try {
        requireAcceptablePassword('short');
      } on ApiError catch (e) {
        expect(e.details?['min_length'], minPasswordLength);
      }
    });

    test('the minimum counts characters, not bytes', () {
      // Eight Cyrillic letters are 16 bytes but exactly eight characters.
      requireAcceptablePassword('Ж' * minPasswordLength);
      expect(
        () => requireAcceptablePassword('Ж' * (minPasswordLength - 1)),
        rejectedAs('too_short'),
      );
    });

    test('a password over 72 bytes is too_long', () {
      expect(
        () => requireAcceptablePassword('x' * (maxPasswordBytes + 1)),
        rejectedAs('too_long'),
      );
    });

    test('the field is reported as given', () {
      expect(
        () => requireAcceptablePassword('x', field: 'new_password'),
        rejectedAs('too_short', field: 'new_password'),
      );
    });
  });

  group('password length', () {
    test('is counted in UTF-8 bytes', () {
      expect(passwordFitsBcrypt('x' * 72), isTrue);
      expect(passwordFitsBcrypt('x' * 73), isFalse);
      expect(passwordFitsBcrypt('Ж' * 36), isTrue);
      expect(passwordFitsBcrypt('Ж' * 37), isFalse);
    });

    test('an over-long password verifies as wrong instead of throwing',
        () async {
      final hash = hashPassword('s3cret');
      expect(await verifyPasswordAsync('x' * 200, hash), isFalse);
    });
  });

  group('HashWorkerPool', () {
    late HashWorkerPool pool;
    tearDown(() => pool.close());

    test('hashes and verifies through its workers', () async {
      pool = HashWorkerPool(2);
      final hash = await pool.hash('s3cret');
      expect(await pool.verify('s3cret', hash), isTrue);
      expect(await pool.verify('wrong', hash), isFalse);
      expect(verifyPassword('s3cret', hash), isTrue);
    });

    test('never starts more workers than its size, however many jobs',
        () async {
      pool = HashWorkerPool(2);
      final hash = hashPassword('s3cret');
      final results = await Future.wait([
        for (var i = 0; i < 8; i++) pool.verify('s3cret', hash),
      ]);
      expect(results, everyElement(isTrue));
      expect(pool.workerCount, 2);
    });

    test('starts workers on demand, and reuses an idle one', () async {
      pool = HashWorkerPool(3);
      expect(pool.workerCount, 0);
      final hash = hashPassword('s3cret');
      await pool.verify('s3cret', hash);
      await pool.verify('s3cret', hash);
      expect(pool.workerCount, 1);
    });

    test('a worker that dies fails its job and is replaced', () async {
      pool = HashWorkerPool(1);
      final hash = hashPassword('s3cret');
      await pool.verify('s3cret', hash);

      final inFlight = pool.verify('s3cret', hash);
      // Let the job reach the worker, then take the worker away.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      pool.debugKillWorkers();
      await expectLater(inFlight, throwsA(isA<StateError>()));

      expect(await pool.verify('s3cret', hash), isTrue);
    });

    test('a job queued behind a dying worker still runs', () async {
      pool = HashWorkerPool(1);
      final hash = hashPassword('s3cret');
      await pool.verify('s3cret', hash);

      final first = pool.verify('s3cret', hash);
      final queued = pool.verify('s3cret', hash);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      pool.debugKillWorkers();

      await expectLater(first, throwsA(isA<StateError>()));
      expect(await queued, isTrue);
    });

    test('close fails queued jobs and refuses new ones', () async {
      pool = HashWorkerPool(1);
      final hash = hashPassword('s3cret');
      final running = pool.verify('s3cret', hash);
      final queued = pool.verify('s3cret', hash);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Subscribed before closing: both fail the moment the pool does.
      final outcomes = Future.wait([
        expectLater(queued, throwsA(isA<StateError>())),
        expectLater(running, throwsA(isA<StateError>())),
      ]);
      await pool.close();
      await outcomes;
      await expectLater(pool.hash('x'), throwsA(isA<StateError>()));
    });

    test('rejects a size below one', () {
      expect(() => HashWorkerPool(0), throwsArgumentError);
    });
  });
}
