import 'package:dio/dio.dart';
import 'package:fpdart/fpdart.dart';
import 'package:structured_log/structured_log.dart';

import '../../../shared/api/auth_api.dart';
import '../../../shared/api/dto/auth_dto.dart';
import '../../../shared/api/failure_mapper.dart';
import '../../../shared/api/token_response.dart';
import '../../../shared/auth/access_token_claims.dart';
import '../../../shared/auth/password_rejection.dart';
import '../../../shared/auth/token_storage.dart';
import '../domain/auth_failure.dart';
import '../domain/auth_repository.dart';

class AuthRepositoryImpl implements AuthRepository {
  final AuthApi _api;
  final TokenStorage _storage;
  final BoundLogger _log;

  AuthRepositoryImpl({
    required AuthApi api,
    required TokenStorage storage,
    required BoundLogger logger,
  }) : _api = api,
       _storage = storage,
       _log = logger.bind({'feature': 'auth'});

  @override
  Future<Either<AuthFailure, Unit>> signIn({
    required String username,
    required String password,
  }) async {
    try {
      final tokens = await _api.signIn(
        AuthApi.passwordGrant,
        username,
        password,
      );
      await _storage.write(sessionFrom(tokens));
      // The username is context, not a secret; neither password nor token is
      // ever logged (decision 48).
      _log.info('auth.signed_in', context: {'username': username});
      return right(unit);
    } on DioException catch (error) {
      final failure = _mapSignIn(error);
      _log.warning(
        'auth.sign_in_refused',
        context: {
          'username': username,
          'failure': failure.runtimeType.toString(),
        },
      );
      return left(failure);
    }
  }

  @override
  Future<void> signOut() async {
    final stored = await _storage.read();
    if (stored != null) {
      try {
        await _api.signOut(stored.refreshToken);
      } on DioException catch (error) {
        // Deliberately swallowed. The local session must end whether or not
        // the server heard about it; leaving the user signed in because the
        // network was down would be the worse failure
        // (`specs/admin-client-auth`).
        _log.warning('auth.revoke_failed', context: {'error': '${error.type}'});
      }
    }
    await _storage.clear();
    _log.info('auth.signed_out');
  }

  @override
  Future<bool> restoreSession() async {
    // This tab already has an access token: a reload, not a new tab. Costs
    // nothing, and — more to the point — keeps a reload out of the renewal
    // race between tabs altogether.
    if (await _storage.read() != null) return true;

    try {
      // No token to present in the cookie mode; the browser attaches it. In
      // the cookie-less mode the shared secret store still holds one, and a
      // new tab must use it rather than renew with nothing.
      final tokens = await _api.refresh(
        AuthApi.refreshGrant,
        await _storage.readRefreshToken(),
      );
      await _storage.write(sessionFrom(tokens));
      return true;
    } on DioException {
      // No session, an expired one, or an unreachable server. All three end
      // at the login screen, and telling them apart would only offer the
      // reader a distinction they cannot act on.
      return false;
    }
  }

  @override
  Future<Either<AuthFailure, Unit>> changePassword({
    required String currentPassword,
    required String newPassword,
    required bool keepOtherSessions,
  }) async {
    try {
      // Read here rather than passed down from the screen: the refresh token
      // is a credential, and the only layer with any business holding one is
      // the one that already stores it. The cubit and the form never see it.
      final held = await _storage.read();
      await _api.changePassword(
        ChangePasswordRequestDto(
          currentPassword: currentPassword,
          newPassword: newPassword,
          keepOtherSessions: keepOtherSessions,
          currentRefreshToken: held?.refreshToken,
        ),
      );
      // Neither password is logged, here or anywhere (decision 48).
      _log.info('auth.password_changed');
      return right(unit);
    } on DioException catch (error) {
      final failure = _mapChangePassword(error);
      _log.warning(
        'auth.password_change_refused',
        context: {'failure': failure.runtimeType.toString()},
      );
      return left(failure);
    }
  }

  @override
  Future<String?> currentUsername() async {
    final tokens = await _storage.read();
    return tokens == null ? null : usernameFromAccessToken(tokens.accessToken);
  }

  @override
  Future<bool> isGlobalAdmin() async {
    final tokens = await _storage.read();
    return tokens != null && isGlobalAdminFromAccessToken(tokens.accessToken);
  }

  /// `POST /v1/auth/change-password` answers in the API's general envelope,
  /// not the RFC 6749 one — but it reuses `invalid_grant` for the one refusal
  /// the screen must name: the current password was wrong.
  AuthFailure _mapChangePassword(DioException error) {
    final response = error.response;
    if (response == null) return AuthFailure.network(message: error.message);
    if (response.statusCode == 429) {
      return AuthFailure.rateLimited(retryAfterOf(response));
    }

    final body = response.data;
    final envelope = body is Map<String, dynamic> ? body : const {};
    if (envelope['error'] == 'invalid_grant') {
      return const AuthFailure.invalidCredentials();
    }
    final details = envelope['details'];
    if (envelope['error'] == 'invalid_request' &&
        details is Map<String, dynamic> &&
        isPasswordRejection(details)) {
      return AuthFailure.passwordRejected(details: details);
    }
    return AuthFailure.unexpected(
      message: envelope['message'] as String? ?? error.message,
    );
  }

  /// Maps the RFC 6749 body the token endpoint answers with — not the API's
  /// general envelope, which is what [mapDioException] handles everywhere
  /// else.
  AuthFailure _mapSignIn(DioException error) {
    final response = error.response;
    if (response == null) {
      // No response at all: timeout, DNS, refused connection.
      return AuthFailure.network(message: error.message);
    }

    if (response.statusCode == 429) {
      return AuthFailure.rateLimited(retryAfterOf(response));
    }

    final body = response.data;
    final envelope = body is Map<String, dynamic> ? body : const {};
    final code = envelope['error'] as String?;
    final reason = envelope['reason'] as String?;

    if (code == 'invalid_grant') {
      // `reason` is this server's one extension to the RFC body. Absent means
      // "wrong credentials" and nothing more specific is ever said.
      return reason == 'email_not_verified'
          ? const AuthFailure.emailNotVerified()
          : const AuthFailure.invalidCredentials();
    }

    return AuthFailure.unexpected(
      message: envelope['error_description'] as String? ?? error.message,
    );
  }
}
