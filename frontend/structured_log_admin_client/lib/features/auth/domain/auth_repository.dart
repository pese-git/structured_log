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

  /// Replaces this account's own password.
  ///
  /// The same call serves both ways in: the forced screen the server puts a
  /// temporary password behind, and the voluntary one in settings
  /// (`specs/admin-client-auth`).
  ///
  /// The session survives it. The server bumps `token_version`, which retires
  /// the access token in hand, but the refresh token stays good — so the next
  /// request renews itself through the interceptor and the user is not sent
  /// back to sign in.
  Future<Either<AuthFailure, Unit>> changePassword({
    required String currentPassword,
    required String newPassword,
  });

  /// The signed-in account's username, read out of the access token.
  ///
  /// `null` when there is no session, or when the token carries no name. There
  /// is no `GET /v1/users/me` in this stage, and the screens that show who is
  /// signed in have nowhere else to get it.
  Future<String?> currentUsername();
}
