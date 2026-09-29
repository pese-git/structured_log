import '../domain/auth_repository.dart';

/// Whether the app starts at the login screen or past it.
///
/// A reload answers from this tab's own access token and never calls the
/// server. A *new* tab has to ask: with the refresh token in an `HttpOnly`
/// cookie, nothing readable here says whether a session exists.
///
/// This used to be a purely local question, and the reasoning then was that
/// probing would add a round trip to every launch to learn what the first
/// 401 would say anyway. That still holds for the reload, which is the
/// common case — it is why the access token is kept per tab rather than in
/// memory (`add-refresh-token-cookie/design.md`, decision 8).
class RestoreSession {
  final AuthRepository _repository;

  const RestoreSession(this._repository);

  Future<bool> call() => _repository.restoreSession();
}
