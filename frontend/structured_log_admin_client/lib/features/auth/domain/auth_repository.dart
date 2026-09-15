import 'package:fpdart/fpdart.dart';

import 'auth_failure.dart';

/// What the auth feature needs from the outside world.
///
/// Declared in `domain` and implemented in `infrastructure` so the use cases —
/// and through them the `Cubit` — depend on this and never on `dio`,
/// `retrofit` or the token storage (design.md decision 32).
abstract interface class AuthRepository {
  /// Exchanges credentials for a session and stores it.
  ///
  /// `Right(unit)` means the tokens are saved and the app may move on; every
  /// [AuthFailure] is an expected outcome the caller has to handle, not a
  /// defect (decision 33).
  Future<Either<AuthFailure, Unit>> signIn({
    required String username,
    required String password,
  });

  /// Revokes the refresh token and clears the local session.
  ///
  /// Never fails: the local session ends whatever the server says, including
  /// when it cannot be reached at all (`specs/admin-client-auth`).
  Future<void> signOut();

  /// Whether a session is already stored — what decides between the login
  /// screen and the app on startup.
  Future<bool> hasSession();
}
