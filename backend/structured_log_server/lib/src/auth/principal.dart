import 'identity_provider.dart';

/// Who a request is acting as, resolved once per request from the single
/// `Authorization: Bearer <...>` header every scheme shares
/// (`log-server-auth`).
///
/// Sealed, and exhaustive by construction: a request is acting as a user, as
/// a project, or as nobody. Two independent nullable fields (an identity and
/// a project id) would admit states that don't exist — both set, or both
/// unset after a credential *was* presented and turned out to be junk.
sealed class Principal {
  const Principal();
}

/// A request carrying a valid access token (`log-server-auth`) — management
/// endpoints and `GET /v1/logs`.
class UserPrincipal extends Principal {
  final VerifiedIdentity identity;

  const UserPrincipal(this.identity);
}

/// A request carrying a valid, unrevoked project secret key — `POST /v1/logs`
/// ingestion, and nothing else.
class ProjectPrincipal extends Principal {
  final int projectId;

  const ProjectPrincipal(this.projectId);
}

/// A request with no credential — or with one that failed to resolve
/// (missing, malformed, expired, revoked, or of an unknown shape).
///
/// Deliberately one state rather than two: every endpoint that requires
/// authentication answers 401 either way (`log-server-auth`), and carrying
/// the reason through the stack would only ever change the message text.
class AnonymousPrincipal extends Principal {
  const AnonymousPrincipal();
}
