import 'package:fpdart/fpdart.dart';

import '../domain/auth_failure.dart';
import '../domain/auth_repository.dart';

/// Replaces the signed-in account's own password.
///
/// One use case for both ways in — the screen the server forces after a
/// temporary password, and the voluntary one in settings. They differ in what
/// happens afterwards, not in what is asked of the server
/// (`specs/admin-client-auth`).
class ChangePassword {
  final AuthRepository _repository;

  const ChangePassword(this._repository);

  Future<Either<AuthFailure, Unit>> call({
    required String currentPassword,
    required String newPassword,
  }) {
    return _repository.changePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
  }
}

/// Who is signed in, for the screens that say so.
class CurrentUsername {
  final AuthRepository _repository;

  const CurrentUsername(this._repository);

  Future<String?> call() => _repository.currentUsername();
}
