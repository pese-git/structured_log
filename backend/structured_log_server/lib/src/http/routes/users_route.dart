import 'package:drift/drift.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../audit/audit_action.dart';
import '../../audit/audit_writer.dart';
import '../../auth/delete_user.dart';
import '../../auth/hashing.dart';
import '../../auth/session.dart';
import '../../errors.dart';
import '../../rbac/access_check.dart';
import '../../rbac/authorizer.dart';
import '../../rbac/token_version.dart';
import '../../storage/database.dart';
import '../../storage/page.dart';
import '../../storage/log_filter.dart' show escapeLike;
import '../json_response.dart';
import '../page_request.dart';
import '../principal_middleware.dart';
import '../rate_limit_middleware.dart';
import '../request_helpers.dart';
import 'groups_route.dart' show soleGroupOwnerError;

part 'users_route.g.dart';

/// `email`/`email_verified_at` are always `null` in this stage: nothing
/// writes them yet — `email` is not accepted by `createUser`/`updateUser`
/// (`design.md` "Delivery Phases", Этап 3, email excluded pending разделы
/// 24–25). Shaped this way from the start rather than added later so the
/// wire format doesn't change out from under a client when they do land.
Map<String, Object?> userJson(User user) {
  return {
    'id': user.id,
    'username': user.username,
    'display_name': user.displayName,
    'email': user.email,
    'email_verified_at': toIso8601Utc(user.emailVerifiedAt),
    'must_change_password': user.mustChangePassword,
    'is_active': user.isActive,
    'deleted_at': toIso8601Utc(user.deletedAt),
    'is_primary_admin': user.isPrimaryAdmin,
    'created_at': toIso8601Utc(user.createdAt),
  };
}

Future<User> _requireUser(StructuredLogDatabase db, int userId) async {
  final user = await (db.select(
    db.users,
  )..where((t) => t.id.equals(userId)))
      .getSingleOrNull();
  if (user == null) throw ApiError.notFound('User not found.');
  return user;
}

/// Renders a finished [DeleteUserOutcome] as the response `DELETE
/// /v1/users/me`/`DELETE /v1/users/:id` share (`docs/api/errors.md`).
Response _deleteResponse(DeleteUserOutcome outcome) {
  switch (outcome.failure) {
    case DeleteUserFailure.cannotDeletePrimaryAdmin:
      throw const ApiError(
        403,
        'cannot_delete_primary_admin',
        'The primary administrator cannot be deleted.',
      );
    case DeleteUserFailure.soleGroupOwner:
      throw soleGroupOwnerError(
        outcome.blockingGroups,
        message: 'Target is the sole owner of one or more groups.',
      );
    case null:
      return Response(204);
  }
}

class UserRoutes {
  final StructuredLogDatabase _db;
  final Authorizer _authorizer;
  final AuditWriter _audit;

  UserRoutes(this._db, this._authorizer, this._audit);

  Router get router => _$UserRoutesRouter(this);

  /// `admin` only. `email` is not accepted yet — `log-server-email-
  /// verification` is not in this stage's scope (`design.md` "Delivery
  /// Phases", Этап 3): accepting it here without a way to issue/send a
  /// verification token would create an account `grant_type=password` can
  /// never let in, once that check lands, with no way to fix it from inside
  /// this stage.
  @Route.post('/v1/users')
  Future<Response> createUser(Request request) async {
    final identity = request.requireUser();
    final roles = await resolveRoles(_authorizer, identity);
    if (!isGlobalAdmin(roles)) throw ApiError.forbidden();

    final body = await readJsonBody(request);
    final username = body['username'];
    final password = body['password'];
    final displayName = body['display_name'];
    if (username is! String || username.isEmpty) {
      throw ApiError.invalidRequest(
        'username is required.',
        details: {'field': 'username', 'reason': 'required'},
      );
    }
    if (password is! String || password.isEmpty) {
      throw ApiError.invalidRequest(
        'password is required.',
        details: {'field': 'password', 'reason': 'required'},
      );
    }
    if (displayName != null && displayName is! String) {
      throw ApiError.invalidRequest(
        'display_name must be a string.',
        details: {'field': 'display_name', 'reason': 'invalid'},
      );
    }

    final existing = await (_db.select(
      _db.users,
    )..where((t) => t.username.equals(username)))
        .getSingleOrNull();
    if (existing != null) {
      throw const ApiError(409, 'username_taken', 'username is already taken.');
    }

    final userId = await _db.transaction(() async {
      final id = await _db.into(_db.users).insert(
            UsersCompanion.insert(
              username: username,
              passwordHash: hashPassword(password),
              displayName: Value(displayName as String?),
              // Always true: a password an admin chose is never the
              // account's own choice (`log-server-forced-password-change`).
              mustChangePassword: const Value(true),
            ),
          );
      await _audit.write(
        action: AuditAction.userCreated,
        targetType: AuditTargetType.user,
        actorUserId: identity.userId,
        targetId: id,
        metadata: {'username': username},
      );
      return id;
    });

    final user = await _requireUser(_db, userId);
    return jsonOk(userJson(user), statusCode: 201);
  }

  /// `admin`, or any `owner` of at least one group — [canSearchUsers]
  /// (уточнение 18.09.2026: the grant/add-member recipient picker needs
  /// this, not just admin's own Users screen).
  @Route.get('/v1/users')
  Future<Response> listUsers(Request request) async {
    final identity = request.requireUser();
    final roles = await resolveRoles(_authorizer, identity);
    if (!canSearchUsers(roles)) throw ApiError.forbidden();

    final params = request.url.queryParameters;
    final (:limit, :cursor) = parsePageRequest(params);
    final username = params['username'];

    // One row more than asked for, dropped by `pageFromProbe` — tells us
    // whether another page exists without a second `COUNT` query.
    final select = _db.select(_db.users)
      ..orderBy([(t) => OrderingTerm.desc(t.id)])
      ..limit(limit + 1);
    if (cursor != null) {
      select.where((t) => t.id.isSmallerThanValue(cursor));
    }
    // Same picker use case as `?name=` on `/v1/groups`/`/v1/projects`
    // (design.md, уточнение 17.09.2026) — narrows the grant-target search,
    // not a general-purpose directory field.
    if (username != null && username.isNotEmpty) {
      select.where(
        (t) => t.username.like('%${escapeLike(username)}%', escapeChar: r'\'),
      );
    }
    final page = pageFromProbe(await select.get(), limit, (user) => user.id);

    return jsonOk({
      'items': page.items.map(userJson).toList(),
      'next_cursor': page.nextCursor?.toString(),
    });
  }

  /// `admin` only. Partial update of `display_name`/`password` — not
  /// `email` yet (see [createUser]).
  @Route('PATCH', '/v1/users/<id>')
  Future<Response> updateUser(Request request, String id) async {
    final identity = request.requireUser();
    final roles = await resolveRoles(_authorizer, identity);
    if (!isGlobalAdmin(roles)) throw ApiError.forbidden();

    final userId = parsePathId(id, 'id');
    await _requireUser(_db, userId);

    final body = await readJsonBody(request);
    final hasDisplayName = body.containsKey('display_name');
    final displayName = body['display_name'];
    final password = body['password'];
    if (hasDisplayName && displayName != null && displayName is! String) {
      throw ApiError.invalidRequest(
        'display_name must be a string.',
        details: {'field': 'display_name', 'reason': 'invalid'},
      );
    }
    if (password != null && password is! String) {
      throw ApiError.invalidRequest(
        'password must be a string.',
        details: {'field': 'password', 'reason': 'invalid'},
      );
    }
    final newPassword = password as String?;

    // Field *names* only — never a value, and never the password in any
    // form (`specs/log-server-audit`).
    final changedFields = <String>[
      if (hasDisplayName) 'display_name',
      if (newPassword != null) 'password',
    ];

    await _db.transaction(() async {
      await (_db.update(
        _db.users,
      )..where((t) => t.id.equals(userId)))
          .write(
        UsersCompanion(
          displayName: hasDisplayName
              ? Value(displayName as String?)
              : const Value.absent(),
          passwordHash: newPassword != null
              ? Value(hashPassword(newPassword))
              : const Value.absent(),
          // A password someone else set is never the account's own choice
          // (`log-server-forced-password-change`) — same rule as creation.
          mustChangePassword:
              newPassword != null ? const Value(true) : const Value.absent(),
        ),
      );
      if (newPassword != null) {
        await revokeAllRefreshTokens(_db, userId);
        await incrementTokenVersion(_db, userId);
      }
      if (changedFields.isNotEmpty) {
        await _audit.write(
          action: AuditAction.userUpdated,
          targetType: AuditTargetType.user,
          actorUserId: identity.userId,
          targetId: userId,
          metadata: {'changed_fields': changedFields},
        );
      }
    });

    final updated = await _requireUser(_db, userId);
    return jsonOk(userJson(updated));
  }

  /// `admin` only — not even `owner` of the target's own group
  /// (`docs/architecture/rbac-and-lifecycle.md`).
  @Route.post('/v1/users/<id>/block')
  Future<Response> blockUser(Request request, String id) async {
    final identity = request.requireUser();
    final roles = await resolveRoles(_authorizer, identity);
    if (!isGlobalAdmin(roles)) throw ApiError.forbidden();

    final userId = parsePathId(id, 'id');
    await _requireUser(_db, userId);

    await _db.transaction(() async {
      await (_db.update(
        _db.users,
      )..where((t) => t.id.equals(userId)))
          .write(const UsersCompanion(isActive: Value(false)));
      await revokeAllRefreshTokens(_db, userId);
      await incrementTokenVersion(_db, userId);
      await _audit.write(
        action: AuditAction.userBlocked,
        targetType: AuditTargetType.user,
        actorUserId: identity.userId,
        targetId: userId,
      );
    });

    final updated = await _requireUser(_db, userId);
    return jsonOk(userJson(updated));
  }

  /// `admin` only. Never reactivates a deleted account — deletion is
  /// permanent (`docs/architecture/rbac-and-lifecycle.md`).
  @Route.post('/v1/users/<id>/unblock')
  Future<Response> unblockUser(Request request, String id) async {
    final identity = request.requireUser();
    final roles = await resolveRoles(_authorizer, identity);
    if (!isGlobalAdmin(roles)) throw ApiError.forbidden();

    final userId = parsePathId(id, 'id');
    final target = await _requireUser(_db, userId);
    if (target.deletedAt != null) {
      throw const ApiError(
        409,
        'deleted_account',
        'Cannot unblock a deleted account.',
      );
    }

    await _db.transaction(() async {
      await (_db.update(
        _db.users,
      )..where((t) => t.id.equals(userId)))
          .write(const UsersCompanion(isActive: Value(true)));
      await _audit.write(
        action: AuditAction.userUnblocked,
        targetType: AuditTargetType.user,
        actorUserId: identity.userId,
        targetId: userId,
      );
    });

    final updated = await _requireUser(_db, userId);
    return jsonOk(userJson(updated));
  }

  /// Any authenticated role, over their own account only — password
  /// required, unlike the admin path (`DELETE /v1/users/:id`), because
  /// nobody else confirmed this is what the account's own owner wants.
  /// Rate-limited by subject (`log-server-rate-limit`), the same way
  /// `POST /v1/auth/change-password` is.
  @Route.delete('/v1/users/me')
  Future<Response> deleteMe(Request request) async {
    final identity = request.requireUser(allowTemporaryPassword: true);
    final attempt = request.rateLimitAttempt;
    await attempt.requireSubject(
      'user:${identity.userId}',
      actorUserId: identity.userId,
    );

    final body = await readJsonBody(request);
    final password = body['password'];
    if (password is! String) {
      throw ApiError.invalidRequest(
        'password is required.',
        details: {'field': 'password', 'reason': 'required'},
      );
    }

    final target = await _requireUser(_db, identity.userId);
    if (!verifyPassword(password, target.passwordHash)) {
      attempt.failed();
      throw const ApiError(
        401,
        'invalid_grant',
        'Current password is incorrect.',
      );
    }
    attempt.succeeded();

    late DeleteUserOutcome outcome;
    await _db.transaction(() async {
      outcome = await deleteUser(_db, target);
      if (outcome.isSuccess) {
        await _audit.write(
          action: AuditAction.userDeleted,
          targetType: AuditTargetType.user,
          actorUserId: identity.userId,
          targetId: identity.userId,
        );
      }
    });

    return _deleteResponse(outcome);
  }

  /// `admin` only, no password — the target's password is never required
  /// for an administrative deletion. `:id == caller` is refused; that path
  /// is [deleteMe] instead, which requires the caller's own password.
  @Route.delete('/v1/users/<id>')
  Future<Response> deleteUserById(Request request, String id) async {
    final identity = request.requireUser();
    final roles = await resolveRoles(_authorizer, identity);
    if (!isGlobalAdmin(roles)) throw ApiError.forbidden();

    final userId = parsePathId(id, 'id');
    if (userId == identity.userId) {
      throw const ApiError(
        400,
        'self_deletion_requires_me',
        'Self-deletion must go through DELETE /v1/users/me.',
      );
    }
    final target = await _requireUser(_db, userId);

    late DeleteUserOutcome outcome;
    await _db.transaction(() async {
      outcome = await deleteUser(_db, target);
      if (outcome.isSuccess) {
        await _audit.write(
          action: AuditAction.userDeleted,
          targetType: AuditTargetType.user,
          actorUserId: identity.userId,
          targetId: userId,
        );
      }
    });

    return _deleteResponse(outcome);
  }
}
