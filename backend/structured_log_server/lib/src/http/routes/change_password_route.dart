import 'package:drift/drift.dart';
import 'package:shelf/shelf.dart';

import '../../auth/hashing.dart';
import '../../errors.dart';
import '../../rbac/token_version.dart';
import '../../storage/database.dart';
import '../auth_middleware.dart';
import '../json_response.dart';
import '../request_helpers.dart';

/// `POST /v1/auth/change-password` — available to any authenticated role
/// over their own account, not just while `must_change_password` is set
/// (`log-server-forced-password-change`).
Future<Response> changePassword(
  StructuredLogDatabase db,
  Request request,
) async {
  final identity = request.verifiedIdentity;
  final body = await readJsonBody(request);
  final currentPassword = body['current_password'];
  final newPassword = body['new_password'];
  if (currentPassword is! String || newPassword is! String) {
    throw ApiError.invalidRequest(
      'current_password and new_password are required.',
    );
  }

  final user = await (db.select(
    db.users,
  )..where((t) => t.id.equals(identity.userId)))
      .getSingle();
  if (!verifyPassword(currentPassword, user.passwordHash)) {
    throw const ApiError(
        401, 'invalid_grant', 'Current password is incorrect.');
  }

  await db.transaction(() async {
    await (db.update(
      db.users,
    )..where((t) => t.id.equals(identity.userId)))
        .write(
      UsersCompanion(
        passwordHash: Value(hashPassword(newPassword)),
        mustChangePassword: const Value(false),
      ),
    );
    await incrementTokenVersion(db, identity.userId);
  });

  return jsonOk(<String, Object?>{});
}
