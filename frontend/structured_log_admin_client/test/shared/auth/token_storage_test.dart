import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log_admin_client/shared/auth/token_pair.dart';
import 'package:structured_log_admin_client/shared/auth/token_storage.dart';

void main() {
  group('InMemoryTokenStorage', () {
    test('round-trips a pair', () async {
      final storage = InMemoryTokenStorage();
      expect(await storage.read(), isNull);

      const pair = TokenPair(accessToken: 'a', refreshToken: 'r');
      await storage.write(pair);
      expect(await storage.read(), pair);

      await storage.clear();
      expect(await storage.read(), isNull);
    });

    test('can start out holding a session', () async {
      const pair = TokenPair(accessToken: 'a', refreshToken: 'r');
      expect(await InMemoryTokenStorage(pair).read(), pair);
    });
  });

  group('TokenPair', () {
    test('compares by value, so a rewrite of the same pair is a no-op', () {
      expect(
        const TokenPair(accessToken: 'a', refreshToken: 'r'),
        const TokenPair(accessToken: 'a', refreshToken: 'r'),
      );
      expect(
        const TokenPair(accessToken: 'a', refreshToken: 'r'),
        isNot(const TokenPair(accessToken: 'a', refreshToken: 'other')),
      );
    });

    test('never prints either token', () {
      const pair = TokenPair(
        accessToken: 'super-secret-access',
        refreshToken: 'super-secret-refresh',
      );
      final printed = pair.toString();
      expect(printed, isNot(contains('super-secret-access')));
      expect(printed, isNot(contains('super-secret-refresh')));
    });
  });
}
