import 'package:fpdart/fpdart.dart';

import '../domain/auth_failure.dart';
import '../domain/auth_repository.dart';

/// Signing in, as one callable thing.
///
/// Thin today — it forwards to the repository — and that is the point: the
/// `Cubit` depends on this, so when signing in grows a second step (recording
/// the account, priming a cache) that step lands here and no screen changes
/// (design.md decision 32).
class SignIn {
  final AuthRepository _repository;

  const SignIn(this._repository);

  Future<Either<AuthFailure, Unit>> call({
    required String username,
    required String password,
  }) {
    // Trimmed because a username pasted from a password manager often carries
    // a trailing space, and the server compares exactly. The password is left
    // untouched: whitespace can be part of it.
    return _repository.signIn(username: username.trim(), password: password);
  }
}
