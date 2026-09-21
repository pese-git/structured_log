import 'package:drift/drift.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../audit/audit_action.dart';
import '../../audit/audit_writer.dart';
import '../../auth/identity_provider.dart';
import '../../errors.dart';
import '../../rbac/access_check.dart';
import '../../rbac/authorizer.dart';
import '../../storage/database.dart';
import '../../storage/page.dart';
import '../../storage/log_filter.dart' show escapeLike;
import '../json_response.dart';
import '../page_request.dart';
import '../principal_middleware.dart';
import '../request_helpers.dart';

part 'projects_route.g.dart';

Map<String, Object?> projectJson(
  Project project, {
  int? entryCount,
  int? totalBytes,
}) {
  final json = <String, Object?>{
    'id': project.id,
    'group_id': project.groupId,
    'name': project.name,
    'retention_days': project.retentionDays,
    'max_entries': project.maxEntries,
    'max_bytes': project.maxBytes,
    'is_blocked': project.isBlocked,
    'created_at': toIso8601Utc(project.createdAt),
  };
  if (entryCount != null) json['entry_count'] = entryCount;
  if (totalBytes != null) json['total_bytes'] = totalBytes;
  return json;
}

Future<Group> _requireGroup(StructuredLogDatabase db, int groupId) async {
  final group = await (db.select(
    db.groups,
  )..where((t) => t.id.equals(groupId))).getSingleOrNull();
  if (group == null) throw ApiError.notFound('Group not found.');
  return group;
}

Future<Project> _requireProject(StructuredLogDatabase db, int projectId) async {
  final project = await (db.select(
    db.projects,
  )..where((t) => t.id.equals(projectId))).getSingleOrNull();
  if (project == null) throw ApiError.notFound('Project not found.');
  return project;
}

class ProjectRoutes {
  final StructuredLogDatabase _db;
  final Authorizer _authorizer;
  final AuditWriter _audit;

  ProjectRoutes(this._db, this._authorizer, this._audit);

  Router get router => _$ProjectRoutesRouter(this);

  /// Every project the caller may read, flat rather than nested under a
  /// group, a page at a time (`log-server-pagination`), newest first. What the
  /// caller may read is part of the query — see `GroupRoutes.listGroups`.
  ///
  /// Flat because RBAC grants a role on a group **or** on a single project,
  /// and a project-scoped role does not cover the enclosing group
  /// (`access_check.dart`'s `_covers`): such a user sees nothing in
  /// `GET /v1/groups`, so a projects-under-a-group endpoint would leave them
  /// with no way to reach the one project they do have. `group_id` narrows
  /// the same list for a screen that shows one group.
  ///
  /// Usage counters are deliberately absent — `entry_count`/`total_bytes`
  /// come from `GET /v1/projects/:id`, one project at a time
  /// (`log-server-quotas`), and computing them for every visible project
  /// would make a selector's request the most expensive one in the API.
  ///
  /// Blocked projects are listed, carrying `is_blocked`: whoever shows the
  /// list decides what to do with them, and hiding a project that exists
  /// would read as its deletion.
  ///
  /// `?name=` narrows to projects whose name contains it (case-insensitive,
  /// `LIKE`), combinable with `group_id` — same filter idiom as `GET
  /// /v1/groups`.
  @Route.get('/v1/projects')
  Future<Response> listProjects(Request request) async {
    final identity = request.requireUser();
    final roles = await resolveRoles(_authorizer, identity);

    final params = request.url.queryParameters;
    final (:limit, :cursor) = parsePageRequest(params);
    final groupIdParam = params['group_id'];
    final groupFilter = groupIdParam == null
        ? null
        : int.tryParse(groupIdParam);
    if (groupIdParam != null && groupFilter == null) {
      throw ApiError.invalidRequest('group_id must be an integer.');
    }
    final name = params['name'];

    final readable = readableScope(roles);
    if (readable.isEmpty) return jsonOk({'items': [], 'next_cursor': null});

    final select = _db.select(_db.projects)
      ..orderBy([(t) => OrderingTerm.desc(t.id)])
      ..limit(limit + 1);
    if (!readable.everything) {
      // A group grant covers the group's projects; a project grant, only
      // that project (`readableScope`).
      select.where(
        (t) =>
            t.groupId.isIn(readable.groupIds) | t.id.isIn(readable.projectIds),
      );
    }
    if (groupFilter != null) {
      select.where((t) => t.groupId.equals(groupFilter));
    }
    if (cursor != null) {
      select.where((t) => t.id.isSmallerThanValue(cursor));
    }
    if (name != null && name.isNotEmpty) {
      select.where(
        (t) => t.name.like('%${escapeLike(name)}%', escapeChar: r'\'),
      );
    }

    final page = pageFromProbe(await select.get(), limit, (p) => p.id);
    return jsonOk({
      'items': page.items.map(projectJson).toList(),
      'next_cursor': page.nextCursor?.toString(),
    });
  }

  /// `owner` of the enclosing group, or `admin` (`log-server-rbac`,
  /// `log-server-quotas`).
  @Route.post('/v1/groups/<groupId>/projects')
  Future<Response> createProject(Request request, String groupId) async {
    final identity = request.requireUser();
    final group = await _requireGroup(_db, parsePathId(groupId, 'groupId'));

    final roles = await resolveRoles(_authorizer, identity);
    if (!canWrite(roles, targetType: ScopeType.group, targetId: group.id)) {
      throw ApiError.forbidden();
    }

    final body = await readJsonBody(request);
    final name = body['name'];
    final retentionDays = body['retention_days'];
    if (name is! String || name.isEmpty) {
      throw ApiError.invalidRequest(
        'name is required.',
        details: {'field': 'name', 'reason': 'required'},
      );
    }
    if (retentionDays is! int) {
      throw ApiError.invalidRequest(
        'retention_days is required.',
        details: {'field': 'retention_days', 'reason': 'required'},
      );
    }
    final maxEntries = body['max_entries'];
    final maxBytes = body['max_bytes'];
    if (maxEntries != null && maxEntries is! int) {
      throw ApiError.invalidRequest(
        'max_entries must be an integer.',
        details: {'field': 'max_entries', 'reason': 'invalid'},
      );
    }
    if (maxBytes != null && maxBytes is! int) {
      throw ApiError.invalidRequest(
        'max_bytes must be an integer.',
        details: {'field': 'max_bytes', 'reason': 'invalid'},
      );
    }

    final projectId = await _db.transaction(() async {
      final id = await _db
          .into(_db.projects)
          .insert(
            ProjectsCompanion.insert(
              groupId: group.id,
              name: name,
              retentionDays: retentionDays,
              maxEntries: Value(maxEntries as int?),
              maxBytes: Value(maxBytes as int?),
            ),
          );
      await _db
          .into(_db.projectUsage)
          .insert(ProjectUsageCompanion.insert(projectId: Value(id)));
      await _audit.write(
        action: AuditAction.projectCreated,
        targetType: AuditTargetType.project,
        actorUserId: identity.userId,
        targetId: id,
        metadata: {
          'name': name,
          'group_id': group.id,
          'retention_days': retentionDays,
        },
      );
      return id;
    });

    final project = await _requireProject(_db, projectId);
    return jsonOk(projectJson(project), statusCode: 201);
  }

  /// `owner`/`admin` (`log-server-quotas`).
  ///
  /// `Route` has no named `patch` constructor — the generic one takes the
  /// verb directly.
  @Route('PATCH', '/v1/projects/<id>')
  Future<Response> updateProjectQuota(Request request, String id) async {
    final identity = request.requireUser();
    final projectId = parsePathId(id, 'id');
    final project = await _requireProject(_db, projectId);

    final roles = await resolveRoles(_authorizer, identity);
    if (!canWrite(
      roles,
      targetType: ScopeType.project,
      targetId: projectId,
      enclosingGroupId: project.groupId,
    )) {
      throw ApiError.forbidden();
    }

    final body = await readJsonBody(request);
    final companion = ProjectsCompanion(
      retentionDays: body.containsKey('retention_days')
          ? Value(body['retention_days'] as int)
          : const Value.absent(),
      maxEntries: body.containsKey('max_entries')
          ? Value(body['max_entries'] as int?)
          : const Value.absent(),
      maxBytes: body.containsKey('max_bytes')
          ? Value(body['max_bytes'] as int?)
          : const Value.absent(),
    );

    // `before` comes from the row read above, before anything is written —
    // the whole value of a quota record is the pair, and reading it afterwards
    // would give the same numbers twice (`docs/api/models.md`).
    final quotaOf = (Project p) => {
      'retention_days': p.retentionDays,
      'max_entries': p.maxEntries,
      'max_bytes': p.maxBytes,
    };

    final updated = await _db.transaction(() async {
      await (_db.update(
        _db.projects,
      )..where((t) => t.id.equals(projectId))).write(companion);

      final updated = await _requireProject(_db, projectId);
      await _audit.write(
        action: AuditAction.projectQuotaUpdated,
        targetType: AuditTargetType.project,
        actorUserId: identity.userId,
        targetId: projectId,
        metadata: {'before': quotaOf(project), 'after': quotaOf(updated)},
      );
      return updated;
    });

    return jsonOk(projectJson(updated));
  }

  /// `owner`/`user` with access, or `admin`; includes
  /// `entry_count`/`total_bytes` (`design.md` decision 22).
  @Route.get('/v1/projects/<id>')
  Future<Response> getProject(Request request, String id) async {
    final identity = request.requireUser();
    final projectId = parsePathId(id, 'id');
    final project = await _requireProject(_db, projectId);

    final roles = await resolveRoles(_authorizer, identity);
    if (!canRead(
      roles,
      targetType: ScopeType.project,
      targetId: projectId,
      enclosingGroupId: project.groupId,
    )) {
      throw ApiError.forbidden();
    }

    final usage = await (_db.select(
      _db.projectUsage,
    )..where((t) => t.projectId.equals(projectId))).getSingleOrNull();

    return jsonOk(
      projectJson(
        project,
        entryCount: usage?.entryCount ?? 0,
        totalBytes: usage?.totalBytes ?? 0,
      ),
    );
  }

  /// `admin` only — not `owner`, even for their own project
  /// (`docs/architecture/rbac-and-lifecycle.md`; same rule `POST
  /// /v1/users/:id/block` uses, `rbac/access_check.dart`'s
  /// `isGlobalAdmin`).
  @Route.post('/v1/projects/<id>/block')
  Future<Response> blockProject(Request request, String id) async {
    return _setBlocked(request, id, blocked: true);
  }

  /// `admin` only. Does not revoke the project's secret keys — that stays a
  /// separate, irreversible action.
  @Route.post('/v1/projects/<id>/unblock')
  Future<Response> unblockProject(Request request, String id) async {
    return _setBlocked(request, id, blocked: false);
  }

  Future<Response> _setBlocked(
    Request request,
    String id, {
    required bool blocked,
  }) async {
    final identity = request.requireUser();
    final roles = await resolveRoles(_authorizer, identity);
    if (!isGlobalAdmin(roles)) throw ApiError.forbidden();

    final projectId = parsePathId(id, 'id');
    await _requireProject(_db, projectId);

    await _db.transaction(() async {
      await (_db.update(_db.projects)..where((t) => t.id.equals(projectId)))
          .write(ProjectsCompanion(isBlocked: Value(blocked)));
      await _audit.write(
        action: blocked
            ? AuditAction.projectBlocked
            : AuditAction.projectUnblocked,
        targetType: AuditTargetType.project,
        actorUserId: identity.userId,
        targetId: projectId,
      );
    });

    final updated = await _requireProject(_db, projectId);
    return jsonOk(projectJson(updated));
  }
}
