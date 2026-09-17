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

  /// Two authorization rules, by what the caller filters on. Filtering by
  /// `scope_type`+`scope_id` — the group/project detail's «Доступ» section —
  /// is open to `admin` or the `owner` of that specific scope
  /// (`canReadRoleAssignmentsForScope`, уточнение 17.09.2026): an owner may
  /// see who else has a role on their own group/project. Every other shape,
  /// including `subject_id` alone (the Edit User dialog, "grants held by
  /// this user") or no filter at all, stays `admin`-only
  /// (`canManageRoleAssignments`, 4.3a) — neither ever wants the whole
  /// table, so there is no pagination, matching `listGroups`/`listProjects`.
  /// `scope_name`/`subject_name` are resolved here (batch lookup, not a
  /// join — no drift `.join()` precedent elsewhere in this package, see
  /// design.md) so the UI never has to round-trip per row to show a
  /// human-readable list.
  @Route.get('/v1/role-assignments')
  Future<Response> listRoleAssignments(Request request) async {
    final identity = request.requireUser();
    final roles = await resolveRoles(_authorizer, identity);

    final params = request.url.queryParameters;
    final subjectId = params['subject_id'] != null
        ? int.tryParse(params['subject_id']!)
        : null;
    final rawScopeType = params['scope_type'];
    final scopeType = rawScopeType != null
        ? _enumByNameOrNull(ScopeType.values, rawScopeType)
        : null;
    final scopeId =
        params['scope_id'] != null ? int.tryParse(params['scope_id']!) : null;

    if (scopeType != null && scopeId != null) {
      int? enclosingGroupId;
      if (scopeType == ScopeType.project) {
        final project = await (_db.select(
          _db.projects,
        )..where((t) => t.id.equals(scopeId)))
            .getSingleOrNull();
        enclosingGroupId = project?.groupId;
      }
      if (!canReadRoleAssignmentsForScope(
        roles,
        scopeType: scopeType,
        scopeId: scopeId,
        enclosingGroupId: enclosingGroupId,
      )) {
        throw ApiError.forbidden();
      }
    } else if (!canManageRoleAssignments(roles)) {
      throw ApiError.forbidden();
    }

    final select = _db.select(_db.roleAssignments)
      ..orderBy([(t) => OrderingTerm.desc(t.id)]);
    if (subjectId != null) {
      select.where(
          (t) => t.subjectType.equals('user') & t.subjectId.equals(subjectId));
    }
    if (scopeType != null) {
      select.where((t) => t.scopeType.equals(scopeType.name));
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

  /// Full rule (`rbac/access_check.dart`'s `canCreateOrRevokeRoleAssignment`,
  /// design.md "Delivery Phases", Этап 4, 4.3): `admin` without restriction;
  /// `owner` of group `G` may grant `role ∈ {owner, user}` on
  /// `scope ∈ {group:G, project ∈ G}`. Authorization runs after resolving
  /// the target scope (needed to know its enclosing group for a `project`
  /// scope) but before touching the subject or inserting — same order as
  /// `projects_route.dart`'s writes. `subject_type: "team"` is still
  /// rejected outright: nothing can create a team to assign a role to yet
  /// (раздел 5.3, same stage, not landed in this task).
  @Route.post('/v1/role-assignments')
  Future<Response> createRoleAssignment(Request request) async {
    final identity = request.requireUser();

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

    int? enclosingGroupId;
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
      enclosingGroupId = project.groupId;
    }

    final roles = await resolveRoles(_authorizer, identity);
    if (!canCreateOrRevokeRoleAssignment(
      roles,
      targetRole: role,
      scopeType: scopeType,
      scopeId: scopeId as int?,
      enclosingGroupId: enclosingGroupId,
    )) {
      throw ApiError.forbidden();
    }

    final subject = await (_db.select(
      _db.users,
    )..where((t) => t.id.equals(subjectId)))
        .getSingleOrNull();
    if (subject == null) throw ApiError.notFound('User not found.');

    final id = await _db.transaction(() async {
      final id = await _db.into(_db.roleAssignments).insert(
            RoleAssignmentsCompanion.insert(
              subjectType: 'user',
              subjectId: subjectId,
              role: role.name,
              scopeType: scopeType.name,
              scopeId: Value(scopeId),
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

  /// Same rule as creating it (`canCreateOrRevokeRoleAssignment`, 4.3) — the
  /// grant's own `role`/`scope_type`/`scope_id` stand in for the request
  /// body a `POST` would have carried, since a `DELETE` has none.
  @Route.delete('/v1/role-assignments/<id>')
  Future<Response> deleteRoleAssignment(Request request, String id) async {
    final identity = request.requireUser();

    final assignmentId = parsePathId(id, 'id');
    final row = await (_db.select(
      _db.roleAssignments,
    )..where((t) => t.id.equals(assignmentId)))
        .getSingleOrNull();
    if (row == null) throw ApiError.notFound('Role assignment not found.');

    final scopeType = _enumByNameOrNull(ScopeType.values, row.scopeType)!;
    int? enclosingGroupId;
    if (scopeType == ScopeType.project && row.scopeId != null) {
      final project = await (_db.select(
        _db.projects,
      )..where((t) => t.id.equals(row.scopeId!)))
          .getSingleOrNull();
      enclosingGroupId = project?.groupId;
    }

    final roles = await resolveRoles(_authorizer, identity);
    if (!canCreateOrRevokeRoleAssignment(
      roles,
      targetRole: _enumByNameOrNull(Role.values, row.role)!,
      scopeType: scopeType,
      scopeId: row.scopeId,
      enclosingGroupId: enclosingGroupId,
    )) {
      throw ApiError.forbidden();
    }

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
