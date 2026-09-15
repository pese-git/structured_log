import 'package:dio/dio.dart';
import 'package:fpdart/fpdart.dart';
import 'package:structured_log/structured_log.dart';

import '../../../shared/api/auth_api.dart';
import '../../../shared/api/failure_mapper.dart';
import '../../../shared/auth/token_pair.dart';
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
      await _storage.write(
        TokenPair(
          accessToken: tokens.accessToken,
          refreshToken: tokens.refreshToken,
        ),
      );
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
  Future<bool> hasSession() async => await _storage.read() != null;

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
