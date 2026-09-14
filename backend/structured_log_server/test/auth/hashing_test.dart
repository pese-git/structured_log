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
}
