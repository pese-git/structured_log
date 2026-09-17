import 'package:drift/drift.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../audit/audit_action.dart';
import '../../audit/audit_writer.dart';
import '../../auth/identity_provider.dart';
import '../../errors.dart';
import '../../rbac/access_check.dart';
import '../../rbac/authorizer.dart';
import '../../rbac/token_version.dart';
import '../../storage/database.dart';
import '../json_response.dart';
import '../principal_middleware.dart';
import '../request_helpers.dart';

part 'role_assignments_route.g.dart';

/// `Role.values.byName`/`ScopeType.values.byName` throw `ArgumentError` for
/// an unrecognized name — request-body validation needs `null` instead, so
/// a bad value becomes `400 invalid_request` rather than an uncaught
/// exception the error middleware would turn into a `500`.
T? _enumByNameOrNull<T extends Enum>(List<T> values, String name) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}

Map<String, Object?> roleAssignmentJson(RoleAssignment row) {
  return {
    'id': row.id,
    'subject_type': row.subjectType,
    'subject_id': row.subjectId,
    'role': row.role,
    'scope_type': row.scopeType,
    'scope_id': row.scopeId,
    'created_at': toIso8601Utc(row.createdAt),
  };
}

class RoleAssignmentRoutes {
  final StructuredLogDatabase _db;
  final Authorizer _authorizer;
  final AuditWriter _audit;

  RoleAssignmentRoutes(this._db, this._authorizer, this._audit);

  Router get router => _$RoleAssignmentRoutesRouter(this);

  /// `admin` only, same rule as create/delete (4.3a). Filters by any
  /// combination of `subject_id`/`scope_type`+`scope_id` — the two shapes
  /// the UI needs are "grants held by this user" (Edit User dialog) and
  /// "grants held on this group/project" (Group/Project detail's «Доступ»
  /// section, design.md, уточнение 17.09.2026); neither ever wants the
  /// whole table, so there is no pagination, matching `listGroups`/
  /// `listProjects`. `scope_name`/`subject_name` are resolved here (batch
  /// lookup, not a join — no drift `.join()` precedent elsewhere in this
  /// package, see design.md) so the UI never has to round-trip per row to
  /// show a human-readable list.
  @Route.get('/v1/role-assignments')
  Future<Response> listRoleAssignments(Request request) async {
    final identity = request.requireUser();
    final roles = await resolveRoles(_authorizer, identity);
    if (!canManageRoleAssignments(roles)) throw ApiError.forbidden();

    final params = request.url.queryParameters;
    final subjectId = params['subject_id'] != null
        ? int.tryParse(params['subject_id']!)
        : null;
    final scopeType = params['scope_type'];
    final scopeId =
        params['scope_id'] != null ? int.tryParse(params['scope_id']!) : null;

    final select = _db.select(_db.roleAssignments)
      ..orderBy([(t) => OrderingTerm.desc(t.id)]);
    if (subjectId != null) {
      select.where(
          (t) => t.subjectType.equals('user') & t.subjectId.equals(subjectId));
    }
    if (scopeType != null) {
      select.where((t) => t.scopeType.equals(scopeType));
    }
    if (scopeId != null) {
      select.where((t) => t.scopeId.equals(scopeId));
    }
    final rows = await select.get();

    final groupIds = {
      for (final r in rows)
        if (r.scopeType == ScopeType.group.name && r.scopeId != null)
          r.scopeId!,
    };
    final projectIds = {
      for (final r in rows)
        if (r.scopeType == ScopeType.project.name && r.scopeId != null)
          r.scopeId!,
    };
    final userIds = {
      for (final r in rows)
        if (r.subjectType == 'user') r.subjectId,
    };

    final groupNames = groupIds.isEmpty
        ? <int, String>{}
        : {
            for (final g in await (_db.select(
              _db.groups,
            )..where((t) => t.id.isIn(groupIds)))
                .get())
              g.id: g.name,
          };
    final projectNames = projectIds.isEmpty
        ? <int, String>{}
        : {
            for (final p in await (_db.select(
              _db.projects,
            )..where((t) => t.id.isIn(projectIds)))
                .get())
              p.id: p.name,
          };
    final userNames = userIds.isEmpty
        ? <int, String>{}
        : {
            for (final u in await (_db.select(
              _db.users,
            )..where((t) => t.id.isIn(userIds)))
                .get())
              u.id: u.username,
          };

    return jsonOk({
      'items': [
        for (final row in rows)
          {
            ...roleAssignmentJson(row),
            'scope_name': switch (row.scopeType) {
              'group' => groupNames[row.scopeId],
              'project' => projectNames[row.scopeId],
              _ => null,
            },
            'subject_name':
                row.subjectType == 'user' ? userNames[row.subjectId] : null,
          },
      ],
    });
  }

  /// `admin` only in this stage's reduced scope (`rbac/access_check.dart`'s
  /// `canManageRoleAssignments`, 4.3a) — an `owner` granting `owner`/`user`
  /// within their own group is the full rule (4.3), a later stage.
  /// `subject_type: "team"` is rejected outright: `subject_type: user` is
  /// all 4.3a covers, since nothing yet can create a team to assign a role
  /// to (`design.md` "Delivery Phases", Этап 3).
  @Route.post('/v1/role-assignments')
  Future<Response> createRoleAssignment(Request request) async {
    final identity = request.requireUser();
    final roles = await resolveRoles(_authorizer, identity);
    if (!canManageRoleAssignments(roles)) throw ApiError.forbidden();

    final body = await readJsonBody(request);
    final subjectType = body['subject_type'];
    if (subjectType != 'user') {
      throw ApiError.invalidRequest(
        subjectType == 'team'
            ? 'subject_type "team" is not supported yet.'
            : 'subject_type must be "user".',
        details: {'field': 'subject_type', 'reason': 'unsupported'},
      );
    }

    final subjectId = body['subject_id'];
    if (subjectId is! int) {
      throw ApiError.invalidRequest(
        'subject_id is required.',
        details: {'field': 'subject_id', 'reason': 'required'},
      );
    }

    final rawRole = body['role'];
    final role =
        rawRole is String ? _enumByNameOrNull(Role.values, rawRole) : null;
    if (role == null) {
      throw ApiError.invalidRequest(
        'role must be one of admin, owner, user.',
        details: {'field': 'role', 'reason': 'invalid'},
      );
    }

    final rawScopeType = body['scope_type'];
    final scopeType = rawScopeType is String
        ? _enumByNameOrNull(ScopeType.values, rawScopeType)
        : null;
    if (scopeType == null) {
      throw ApiError.invalidRequest(
        'scope_type must be one of global, group, project.',
        details: {'field': 'scope_type', 'reason': 'invalid'},
      );
    }

    final scopeId = body['scope_id'];
    if (scopeType == ScopeType.global) {
      if (scopeId != null) {
        throw ApiError.invalidRequest(
          'scope_id must be absent when scope_type is "global".',
          details: {'field': 'scope_id', 'reason': 'invalid'},
        );
      }
    } else if (scopeId is! int) {
      throw ApiError.invalidRequest(
        'scope_id is required unless scope_type is "global".',
        details: {'field': 'scope_id', 'reason': 'required'},
      );
    }

    final subject = await (_db.select(
      _db.users,
    )..where((t) => t.id.equals(subjectId)))
        .getSingleOrNull();
    if (subject == null) throw ApiError.notFound('User not found.');

    if (scopeType == ScopeType.group) {
      final group = await (_db.select(
        _db.groups,
      )..where((t) => t.id.equals(scopeId as int)))
          .getSingleOrNull();
      if (group == null) throw ApiError.notFound('Group not found.');
    } else if (scopeType == ScopeType.project) {
      final project = await (_db.select(
        _db.projects,
      )..where((t) => t.id.equals(scopeId as int)))
          .getSingleOrNull();
      if (project == null) throw ApiError.notFound('Project not found.');
    }

    final id = await _db.transaction(() async {
      final id = await _db.into(_db.roleAssignments).insert(
            RoleAssignmentsCompanion.insert(
              subjectType: 'user',
              subjectId: subjectId,
              role: role.name,
              scopeType: scopeType.name,
              scopeId: Value(scopeId as int?),
            ),
          );
      // Single increment, not cascading: `subject_type: user` only in this
      // stage — the cascading update for `subject_type: team` has no caller
      // yet (`rbac/token_version.dart`).
      await incrementTokenVersion(_db, subjectId);
      await _audit.write(
        action: AuditAction.roleAssignmentCreated,
        targetType: AuditTargetType.roleAssignment,
        actorUserId: identity.userId,
        targetId: id,
        metadata: {
          'subject_type': 'user',
          'subject_id': subjectId,
          'role': role.name,
          'scope_type': scopeType.name,
          'scope_id': scopeId,
        },
      );
      return id;
    });

    final row = await (_db.select(
      _db.roleAssignments,
    )..where((t) => t.id.equals(id)))
        .getSingle();
    return jsonOk(roleAssignmentJson(row), statusCode: 201);
  }

  /// Same rule as creating it (4.3a: `admin` only in this stage).
  @Route.delete('/v1/role-assignments/<id>')
  Future<Response> deleteRoleAssignment(Request request, String id) async {
    final identity = request.requireUser();
    final roles = await resolveRoles(_authorizer, identity);
    if (!canManageRoleAssignments(roles)) throw ApiError.forbidden();

    final assignmentId = parsePathId(id, 'id');
    final row = await (_db.select(
      _db.roleAssignments,
    )..where((t) => t.id.equals(assignmentId)))
        .getSingleOrNull();
    if (row == null) throw ApiError.notFound('Role assignment not found.');

    await _db.transaction(() async {
      await (_db.delete(
        _db.roleAssignments,
      )..where((t) => t.id.equals(assignmentId)))
          .go();
      if (row.subjectType == 'user') {
        await incrementTokenVersion(_db, row.subjectId);
      }
      await _audit.write(
        action: AuditAction.roleAssignmentRevoked,
        targetType: AuditTargetType.roleAssignment,
        actorUserId: identity.userId,
        targetId: assignmentId,
        metadata: {
          'subject_type': row.subjectType,
          'subject_id': row.subjectId,
          'role': row.role,
          'scope_type': row.scopeType,
          'scope_id': row.scopeId,
        },
      );
    });

    return Response(204);
  }
}
