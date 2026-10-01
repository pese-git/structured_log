import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log_admin_client/shared/auth/session_store.dart';
import 'package:structured_log_admin_client/shared/auth/token_pair.dart';
import 'package:structured_log_admin_client/shared/auth/token_storage.dart';

/// The per-tab half, without a browser.
class _FakeSessionStore implements SessionStore {
  String? value;

  @override
  String? read() => value;

  @override
  void write(String? next) => value = next;
}

/// The platform-secure half, without a keychain.
class _FakeSecretStore implements SecretStore {
  String? value;
  var writes = 0;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String? next) async {
    writes++;
    value = next;
  }
}

void main() {
  late _FakeSessionStore session;
  late _FakeSecretStore secret;
  late SplitTokenStorage storage;

  setUp(() {
    session = _FakeSessionStore();
    secret = _FakeSecretStore();
    storage = SplitTokenStorage(accessStore: session, refreshStore: secret);
  });

  test('the two halves live in different places', () async {
    await storage.write(const TokenPair(accessToken: 'a', refreshToken: 'r'));

    expect(session.value, 'a', reason: 'the access token is per-tab');
    expect(secret.value, 'r');
  });

  test(
    'a session whose refresh token the browser holds stores only one',
    () async {
      await storage.write(const TokenPair(accessToken: 'a'));

      expect(session.value, 'a');
      expect(
        secret.value,
        isNull,
        reason:
            'in cookie mode the refresh token must never reach any storage '
            'this page can read — that is the whole point of the change',
      );
    },
  );

  test('switching to cookie mode removes the token already stored', () async {
    // The hazard: sign in against a server without the cookie, then the
    // operator turns it on. Leaving the old value behind would keep a live
    // 30-day credential in browser storage indefinitely.
    await storage.write(const TokenPair(accessToken: 'a', refreshToken: 'r'));
    await storage.write(const TokenPair(accessToken: 'a2'));

    expect(secret.value, isNull);
  });

  test('reads back what was written, in both modes', () async {
    await storage.write(const TokenPair(accessToken: 'a', refreshToken: 'r'));
    expect(
      await storage.read(),
      const TokenPair(accessToken: 'a', refreshToken: 'r'),
    );

    await storage.write(const TokenPair(accessToken: 'b'));
    expect(await storage.read(), const TokenPair(accessToken: 'b'));
  });

  test(
    'no access token is no session, even with a refresh token stored',
    () async {
      secret.value = 'left-over';

      expect(
        await storage.read(),
        isNull,
        reason:
            'a tab without an access token has to restore the session by '
            'asking the server, not by half-trusting what it found',
      );
    },
  );

  test('clearing empties both halves', () async {
    await storage.write(const TokenPair(accessToken: 'a', refreshToken: 'r'));

    await storage.clear();

    expect(session.value, isNull);
    expect(secret.value, isNull);
    expect(await storage.read(), isNull);
  });

  test('clearing reaches the keychain even in cookie mode', () async {
    // Signing out must not depend on whether this session happened to store a
    // refresh token: a value from an earlier, non-cookie sign-in could still
    // be sitting there.
    secret.value = 'left-over';
    await storage.write(const TokenPair(accessToken: 'a'));

    await storage.clear();

    expect(secret.value, isNull);
  });
}
