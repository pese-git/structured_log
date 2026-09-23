import 'package:fpdart/fpdart.dart';

import '../domain/auth_failure.dart';
import '../domain/auth_repository.dart';

/// Replaces the signed-in account's own password.
///
/// One use case for both ways in — the screen the server forces after a
/// temporary password, and the voluntary one in settings. What they ask of
/// the server differs in one bit only: settings offers the reader a way to
/// leave their other devices signed in, and the forced screen does not
/// (`specs/admin-client-auth`).
class ChangePassword {
  final AuthRepository _repository;

  const ChangePassword(this._repository);

  Future<Either<AuthFailure, Unit>> call({
    required String currentPassword,
    required String newPassword,
    required bool keepOtherSessions,
  }) {
    return _repository.changePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
      keepOtherSessions: keepOtherSessions,
    );
  }
}

/// Who is signed in, for the screens that say so.
class CurrentUsername {
  final AuthRepository _repository;

  const CurrentUsername(this._repository);

  Future<String?> call() => _repository.currentUsername();
}

/// Whether to offer the administrator-only parts of the application.
///
/// Named for what it reads, not for what it gates, because it gates nothing:
/// the server refuses an unauthorised caller whatever this answers. A `true`
/// here buys a menu item; a `false` avoids offering a screen that would only
/// show a refusal.
class IsGlobalAdmin {
  final AuthRepository _repository;

  const IsGlobalAdmin(this._repository);

  Future<bool> call() => _repository.isGlobalAdmin();
}
