import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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

/// The real one: platform-backed secure storage, never shared preferences
/// (decision 20).
class SecureTokenStorage implements TokenStorage {
  final FlutterSecureStorage _storage;

  static const _accessKey = 'structured_log.access_token';
  static const _refreshKey = 'structured_log.refresh_token';

  const SecureTokenStorage(this._storage);

  @override
  Future<TokenPair?> read() async {
    final access = await _storage.read(key: _accessKey);
    final refresh = await _storage.read(key: _refreshKey);
    // A half-written pair is no session at all: refreshing needs the refresh
    // token, and an access token alone would send the app into a signed-in
    // state it cannot recover from.
    if (access == null || refresh == null) return null;
    return TokenPair(accessToken: access, refreshToken: refresh);
  }

  @override
  Future<void> write(TokenPair tokens) async {
    await _storage.write(key: _accessKey, value: tokens.accessToken);
    await _storage.write(key: _refreshKey, value: tokens.refreshToken);
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
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
