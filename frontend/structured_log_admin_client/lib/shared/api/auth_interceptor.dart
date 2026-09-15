import 'dart:async';

import 'package:dio/dio.dart';

import '../auth/token_pair.dart';
import '../auth/token_storage.dart';

/// Attaches the access token, and renews it once when the server says it is
/// no longer good.
///
/// The renewal lives here rather than in each repository so that a screen
/// never sees the 401 that was recoverable: it either gets the answer to the
/// request it made, or a failure that is genuinely final
/// (`specs/admin-client-auth`).
class AuthInterceptor extends Interceptor {
  final TokenStorage _storage;

  /// Exchanges a refresh token for a new pair, or returns `null` when the
  /// server refuses. Injected rather than calling `AuthApi` directly: that
  /// client runs on the very `Dio` this interceptor is installed in, and a
  /// refresh answered with 401 would drive it back through here.
  final Future<TokenPair?> Function(String refreshToken) _refresh;

  /// The session ended and cannot be recovered — the app returns to sign-in.
  /// Called once per expiry, after the stored tokens are cleared.
  final void Function()? onSessionExpired;

  /// Replays the original request after a successful refresh. Separate from
  /// the `Dio` under this interceptor for the same reason as [_refresh].
  final Dio _retryClient;

  /// Marks a request that must go out without a token.
  static const skipAuthExtra = 'structured_log.skip_auth';

  /// The token endpoint is exempt by path, not only by flag. It authenticates
  /// the caller itself, so it needs no Authorization header — and, more to the
  /// point, a 401 from it means "wrong password" or "this refresh token is
  /// spent". Refreshing in response to either would turn a failed sign-in into
  /// a renewal attempt, and a refused refresh into an infinite one.
  static const _tokenPath = '/v1/auth/token';

  /// Marks the one replay a request is allowed. Its presence is what makes
  /// "exactly once" true even when several requests fail at the same moment.
  static const _retriedExtra = 'structured_log.retried';

  /// In-flight refresh, shared by every request that hit a 401 while it runs.
  /// Without this, five parallel requests would each spend the refresh token —
  /// and on a server that rotates them, four would be spending one that had
  /// just been revoked.
  Future<TokenPair?>? _refreshInFlight;

  AuthInterceptor({
    required TokenStorage storage,
    required Future<TokenPair?> Function(String refreshToken) refresh,
    required Dio retryClient,
    this.onSessionExpired,
  }) : _storage = storage,
       _refresh = refresh,
       _retryClient = retryClient;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (_isExempt(options)) {
      return handler.next(options);
    }
    final tokens = await _storage.read();
    if (tokens != null) {
      options.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    final isRecoverable =
        err.response?.statusCode == 401 &&
        !_isExempt(options) &&
        options.extra[_retriedExtra] != true;
    if (!isRecoverable) return handler.next(err);

    final stored = await _storage.read();
    if (stored == null) return handler.next(err);

    final renewed = await _runRefresh(stored.refreshToken);
    if (renewed == null) {
      // The refresh token is spent, revoked, or the account is blocked.
      // Nothing the app can do but start over.
      await _storage.clear();
      onSessionExpired?.call();
      return handler.next(err);
    }

    try {
      final response = await _retryClient.fetch<dynamic>(
        options
          ..headers['Authorization'] = 'Bearer ${renewed.accessToken}'
          ..extra[_retriedExtra] = true,
      );
      handler.resolve(response);
    } on DioException catch (retryError) {
      // A second 401 is not another refresh: the token is fresh, so the
      // refusal is about this request, not the session.
      handler.next(retryError);
    }
  }

  static bool _isExempt(RequestOptions options) =>
      options.extra[skipAuthExtra] == true || options.path == _tokenPath;

  Future<TokenPair?> _runRefresh(String refreshToken) {
    final existing = _refreshInFlight;
    if (existing != null) return existing;

    final attempt = _refresh(refreshToken)
        .then((tokens) async {
          if (tokens != null) await _storage.write(tokens);
          return tokens;
        })
        .whenComplete(() => _refreshInFlight = null);

    _refreshInFlight = attempt;
    return attempt;
  }
}
