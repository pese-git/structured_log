import 'package:drift/drift.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../audit/audit_action.dart';
import '../../audit/audit_writer.dart';
import '../../auth/hashing.dart';
import '../../auth/session.dart';
import '../../errors.dart';
import '../../rbac/token_version.dart';
import '../../storage/database.dart';
import '../json_response.dart';
import '../principal_middleware.dart';
import '../rate_limit_middleware.dart';
import '../request_helpers.dart';

part 'change_password_route.g.dart';

class ChangePasswordRoutes {
  final StructuredLogDatabase _db;
  final AuditWriter _audit;

  ChangePasswordRoutes(this._db, this._audit);

  Router get router => _$ChangePasswordRoutesRouter(this);

  /// Available to any authenticated role over their own account, not just
  /// while `must_change_password` is set
  /// (`log-server-forced-password-change`).
  @Route.post('/v1/auth/change-password')
  Future<Response> changePassword(Request request) async {
    // The one implemented endpoint the forced-password-change gate exempts —
    // it is how the flag gets cleared (`log-server-forced-password-change`).
    final identity = request.requireUser(allowTemporaryPassword: true);
    // Subject is the authenticated user, not a submitted string
    // (`log-server-rate-limit`).
    final attempt = request.rateLimitAttempt;
    // The actor is recorded here and not at the token endpoint, because this
    // subject came out of an already-verified token — an id, not a string
    // somebody submitted.
    await attempt.requireSubject(
      'user:${identity.userId}',
      actorUserId: identity.userId,
    );

    final body = await readJsonBody(request);
    final currentPassword = body['current_password'];
    final newPassword = body['new_password'];
    if (currentPassword is! String || newPassword is! String) {
      throw ApiError.invalidRequest(
        'current_password and new_password are required.',
      );
    }

    requireAcceptablePassword(newPassword, field: 'new_password');

    // Both optional, and their defaults are what an old client, a `curl` and a
    // forgetful new client all get: absent means "sign the other sessions
    // out". The flag is spelled as the *exception* for that reason — the
    // safe behaviour must not be something a caller has to remember to ask
    // for (`log-server-forced-password-change`).
    final rawKeepOtherSessions = body['keep_other_sessions'];
    if (rawKeepOtherSessions != null && rawKeepOtherSessions is! bool) {
      throw ApiError.invalidRequest(
        'keep_other_sessions must be a boolean.',
        details: {'field': 'keep_other_sessions', 'reason': 'invalid'},
      );
    }
    final keepOtherSessions = rawKeepOtherSessions as bool? ?? false;

    final rawCurrentRefreshToken = body['current_refresh_token'];
    if (rawCurrentRefreshToken != null && rawCurrentRefreshToken is! String) {
      throw ApiError.invalidRequest(
        'current_refresh_token must be a string.',
        details: {'field': 'current_refresh_token', 'reason': 'invalid'},
      );
    }
    final currentRefreshToken = rawCurrentRefreshToken as String?;

    final user = await (_db.select(
      _db.users,
    )..where((t) => t.id.equals(identity.userId))).getSingle();
    if (!await verifyPasswordAsync(currentPassword, user.passwordHash)) {
      attempt.failed();
      throw const ApiError(
        401,
        'invalid_grant',
        'Current password is incorrect.',
      );
    }
    attempt.succeeded();

    // Before the transaction: hashing inside it would hold the write lock for
    // the ~130 ms bcrypt takes.
    final newHash = await hashPasswordAsync(newPassword);
    await _db.transaction(() async {
      await (_db.update(
        _db.users,
      )..where((t) => t.id.equals(identity.userId))).write(
        UsersCompanion(
          passwordHash: Value(newHash),
          mustChangePassword: const Value(false),
        ),
      );
      await incrementTokenVersion(_db, identity.userId);
      // `token_version` alone only kills access tokens; a refresh token
      // outlives it and mints a new one, so a password changed because it was
      // compromised would not have removed whoever knew it. Inside the same
      // transaction as the new hash: a sweep that survived a rolled-back
      // password change would sign everyone out for nothing.
      //
      // The caller's own session is named by the token it presents, which is
      // all the server has to go on — `Authorization` carries an access token,
      // and `refresh_tokens` holds hashes that say nothing about which device
      // is asking. Naming none of them ends this session too
      // (`revokeRefreshTokensExcept`).
      final revoked = keepOtherSessions
          ? 0
          : await revokeRefreshTokensExcept(
              _db,
              identity.userId,
              exceptTokenHash: currentRefreshToken == null
                  ? null
                  : hashToken(currentRefreshToken),
            );
      // Neither password appears, here or anywhere, and neither does the token
      // that was spared — it is a live credential. How many sessions ended is
      // a fact about the account, and the one thing here somebody reading the
      // journal after an incident actually needs.
      await _audit.write(
        action: AuditAction.passwordChanged,
        targetType: AuditTargetType.user,
        actorUserId: identity.userId,
        targetId: identity.userId,
        metadata: {'other_sessions_revoked': revoked},
      );
    });

    return jsonOk(<String, Object?>{});
  }
}
