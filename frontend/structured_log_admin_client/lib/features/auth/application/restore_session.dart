import '../domain/auth_repository.dart';

/// Whether the app starts at the login screen or past it.
///
/// Only asks whether tokens are stored; it does not call the server. A stored
/// pair that turns out to be dead is handled where it surfaces — the first
/// request 401s, the interceptor tries to renew, and a refusal ends the
/// session (`specs/admin-client-auth`). Probing here would add a round trip
/// to every launch to learn the same thing a moment later.
class RestoreSession {
  final AuthRepository _repository;

  const RestoreSession(this._repository);

  Future<bool> call() => _repository.hasSession();
}
