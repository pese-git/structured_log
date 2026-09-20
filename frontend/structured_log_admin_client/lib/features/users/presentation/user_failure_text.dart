import '../../../l10n/app_localizations.dart';
import '../../../shared/api/api_failure.dart';
import '../../../shared/auth/password_rejection.dart';

/// What to tell someone about a refused request on the users screen.
///
/// A separate function from `resource_failure_text.dart`'s
/// `describeApiFailure`, not a shared one: there a 409 is almost always a
/// name already taken, but here a 409 might just as well be
/// `sole_group_owner` or `deleted_account` — codes that need their own words,
/// not the resources screen's generic "name taken".
String describeUserFailure(AppLocalizations l10n, ApiFailure failure) {
  // A refused password is the one 400 here with something specific to say; the
  // server's own message for it is English.
  if (failure is InvalidRequestFailure) {
    final password = describePasswordRejection(l10n, failure.details);
    if (password != null) return password;
  }
  return _describe(l10n, failure);
}

String _describe(AppLocalizations l10n, ApiFailure failure) =>
    switch (failure) {
      ForbiddenFailure(:final code)
          when code == 'cannot_delete_primary_admin' =>
        l10n.usersFailureCannotDeletePrimaryAdmin,
      ForbiddenFailure() => l10n.usersFailureForbidden,
      ConflictFailure(:final code) when code == 'username_taken' =>
        l10n.usersFailureUsernameTaken,
      ConflictFailure(:final code) when code == 'deleted_account' =>
        l10n.usersFailureDeletedAccount,
      ConflictFailure(:final code) when code == 'sole_group_owner' =>
        l10n.usersFailureSoleGroupOwner,
      ConflictFailure() => l10n.usersFailureConflict,
      InvalidRequestFailure(:final code)
          when code == 'self_deletion_requires_me' =>
        l10n.usersFailureSelfDeletion,
      InvalidRequestFailure(:final message) =>
        message ?? l10n.usersFailureInvalidRequest,
      NotFoundFailure() => l10n.usersFailureNotFound,
      UnauthorizedFailure() => l10n.usersFailureUnauthorized,
      RateLimitedFailure(:final retryAfter) => l10n.usersFailureRateLimited(
        retryAfter.inSeconds,
      ),
      NetworkFailure() => l10n.usersFailureNetwork,
      ServerFailure(:final statusCode) => l10n.usersFailureServer(statusCode),
    };

/// The groups a `409 sole_group_owner` names as blocked by the deletion —
/// `{"blocking_groups": [{"id": ..., "name": ..., "created_at": ...}, ...]}`
/// (`docs/api/errors.md`), read directly out of `ConflictFailure.details`
/// rather than through a DTO: this is the one place this client ever reads
/// this shape, and a `GroupDto.fromJson` round-trip would buy nothing a
/// direct map read does not already have.
///
/// The id travels alongside the name — `SoleOwnerConflictDialog`'s
/// «Выдать роль» button on each row needs it to open `GrantAccessDialog`
/// already scoped to that group.
List<({int id, String name})> blockingGroups(ApiFailure failure) {
  if (failure is! ConflictFailure) return const [];
  final groups = failure.details?['blocking_groups'];
  if (groups is! List) return const [];
  return [
    for (final group in groups)
      if (group is Map && group['id'] is int && group['name'] is String)
        (id: group['id'] as int, name: group['name'] as String),
  ];
}
