import 'package:drift/drift.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../audit/audit_action.dart';
import '../../audit/audit_writer.dart';
import '../../auth/hashing.dart';
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
      // Neither password appears, here or anywhere. The fact that this account
      // changed its own password at this time is the whole of what the journal
      // is entitled to.
      await _audit.write(
        action: AuditAction.passwordChanged,
        targetType: AuditTargetType.user,
        actorUserId: identity.userId,
        targetId: identity.userId,
      );
    });

    return jsonOk(<String, Object?>{});
  }
}
