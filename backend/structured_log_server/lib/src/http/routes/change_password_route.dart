import 'package:drift/drift.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../auth/hashing.dart';
import '../../errors.dart';
import '../../rbac/token_version.dart';
import '../../storage/database.dart';
import '../json_response.dart';
import '../principal_middleware.dart';
import '../request_helpers.dart';

part 'change_password_route.g.dart';

class ChangePasswordRoutes {
  final StructuredLogDatabase _db;

  ChangePasswordRoutes(this._db);

  Router get router => _$ChangePasswordRoutesRouter(this);

  /// Available to any authenticated role over their own account, not just
  /// while `must_change_password` is set
  /// (`log-server-forced-password-change`).
  @Route.post('/v1/auth/change-password')
  Future<Response> changePassword(Request request) async {
    // The one implemented endpoint the forced-password-change gate exempts —
    // it is how the flag gets cleared (`log-server-forced-password-change`).
    final identity = request.requireUser(allowTemporaryPassword: true);
    final body = await readJsonBody(request);
    final currentPassword = body['current_password'];
    final newPassword = body['new_password'];
    if (currentPassword is! String || newPassword is! String) {
      throw ApiError.invalidRequest(
        'current_password and new_password are required.',
      );
    }

    final user = await (_db.select(
      _db.users,
    )..where((t) => t.id.equals(identity.userId)))
        .getSingle();
    if (!verifyPassword(currentPassword, user.passwordHash)) {
      throw const ApiError(
          401, 'invalid_grant', 'Current password is incorrect.');
    }

    await _db.transaction(() async {
      await (_db.update(
        _db.users,
      )..where((t) => t.id.equals(identity.userId)))
          .write(
        UsersCompanion(
          passwordHash: Value(hashPassword(newPassword)),
          mustChangePassword: const Value(false),
        ),
      );
      await incrementTokenVersion(_db, identity.userId);
    });

    return jsonOk(<String, Object?>{});
  }
}
