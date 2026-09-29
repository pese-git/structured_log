import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'session_store.dart';
import 'token_pair.dart';

/// Where the session lives between launches.
///
/// An interface rather than a concrete class so tests never touch a real
/// keychain: `flutter_secure_storage` needs platform channels that a widget
/// test and a CI runner do not have (design.md decision 20 / Risks).
abstract interface class TokenStorage {
  Future<TokenPair?> read();

  Future<void> write(TokenPair tokens);

  /// Called on sign-out and whenever a refresh is refused. Must succeed even
  /// when the server could not be reached — the local session ends either
  /// way (`specs/admin-client-auth`).
  Future<void> clear();
}

/// The platform's own secret store, behind an interface so the composition
/// below can be tested without a keychain.
abstract interface class SecretStore {
  Future<String?> read();

  Future<void> write(String? value);
}

/// `flutter_secure_storage`, which is what this means off the web.
///
/// On the web it is `localStorage` with the decrypting key stored beside the
/// ciphertext, which is why the refresh token stopped being kept here at all
/// when the server can hold it in an `HttpOnly` cookie instead
/// (`add-refresh-token-cookie/proposal.md`). What still passes through here
/// is the refresh token of a deployment that cannot use the cookie — a client
/// served from a different origin than its API.
class PlatformSecretStore implements SecretStore {
  final FlutterSecureStorage _storage;

  static const _key = 'structured_log.refresh_token';

  const PlatformSecretStore(this._storage);

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String? value) => value == null
      ? _storage.delete(key: _key)
      : _storage.write(key: _key, value: value);
}

/// The session split across the two places its halves belong.
///
/// The access token goes to [SessionStore] — per tab, surviving a reload. The
/// refresh token goes to [SecretStore], and only when the client is holding
/// one at all: under the cookie mode the server keeps it and [TokenPair.refreshToken]
/// is `null`.
///
/// Writing a pair without a refresh token *erases* whatever was stored
/// before, rather than leaving it. An operator who turns the cookie on would
/// otherwise leave every already-signed-in browser holding a live 30-day
/// credential in storage that this page can read — the exact thing being
/// moved out of reach.
class SplitTokenStorage implements TokenStorage {
  final SessionStore _accessStore;
  final SecretStore _refreshStore;

  const SplitTokenStorage({
    required SessionStore accessStore,
    required SecretStore refreshStore,
  }) : _accessStore = accessStore,
       _refreshStore = refreshStore;

  /// The access token is what says a session exists here. A tab holding only
  /// a refresh token has nothing to authenticate with and must restore the
  /// session by asking the server, not by half-trusting what it found.
  @override
  Future<TokenPair?> read() async {
    final access = _accessStore.read();
    if (access == null) return null;
    return TokenPair(
      accessToken: access,
      refreshToken: await _refreshStore.read(),
    );
  }

  @override
  Future<void> write(TokenPair tokens) async {
    _accessStore.write(tokens.accessToken);
    await _refreshStore.write(tokens.refreshToken);
  }

  /// Clears both halves unconditionally — including the secret store this
  /// session may never have written to, since a value from an earlier
  /// sign-in against a server without the cookie could still be sitting
  /// there.
  @override
  Future<void> clear() async {
    _accessStore.write(null);
    await _refreshStore.write(null);
  }
}

/// Holds the pair in memory for the life of the object.
///
/// For tests and for the gallery — anywhere a real keychain is unavailable or
/// unwanted. Shipping it in `lib/` rather than `test/` is deliberate: widget
/// tests in other packages and the example app both need it, and a fake that
/// only exists under `test/` cannot be imported.
class InMemoryTokenStorage implements TokenStorage {
  TokenPair? _tokens;

  InMemoryTokenStorage([this._tokens]);

  @override
  Future<TokenPair?> read() async => _tokens;

  @override
  Future<void> write(TokenPair tokens) async => _tokens = tokens;

  @override
  Future<void> clear() async => _tokens = null;
}
