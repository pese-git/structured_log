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
  /// This session survives it, and by default no other one does. The server
  /// bumps `token_version`, which retires the access token in hand, and
  /// revokes every refresh token but the one this client presents — so the
  /// next request renews itself through the interceptor while every other
  /// device is sent back to sign in. That is the point: a password changed
  /// because somebody else learned it has to remove them, and `token_version`
  /// alone does not (a refresh token outlives it and mints a fresh access
  /// token).
  ///
  /// [keepOtherSessions] is the reader's opt-out, offered in account settings
  /// and nowhere else — the forced screen replaces a password an
  /// administrator chose, and there is nothing there worth keeping signed in.
  Future<Either<AuthFailure, Unit>> changePassword({
    required String currentPassword,
    required String newPassword,
    required bool keepOtherSessions,
  });

  /// The signed-in account's username, read out of the access token.
  ///
  /// `null` when there is no session, or when the token carries no name. There
  /// is no `GET /v1/users/me` in this stage, and the screens that show who is
  /// signed in have nowhere else to get it.
  Future<String?> currentUsername();

  /// Whether the access token in hand claims `admin` at global scope.
  ///
  /// Read from the token rather than asked of the server, because no endpoint
  /// in this stage reports the caller's own roles. It decides what the
  /// application **offers**, never what it allows: the server re-derives roles
  /// on every request and refuses regardless
  /// (`shared/auth/access_token_claims.dart`).
  Future<bool> isGlobalAdmin();
}
