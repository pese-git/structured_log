import '../domain/auth_repository.dart';

/// Signing out. Cannot fail — see [AuthRepository.signOut].
class SignOut {
  final AuthRepository _repository;

  const SignOut(this._repository);

  Future<void> call() => _repository.signOut();
}
