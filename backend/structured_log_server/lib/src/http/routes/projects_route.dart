import 'package:drift/drift.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../auth/identity_provider.dart';
import '../../errors.dart';
import '../../rbac/access_check.dart';
import '../../rbac/authorizer.dart';
import '../../storage/database.dart';
import '../json_response.dart';
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
  )..where((t) => t.id.equals(groupId)))
      .getSingleOrNull();
  if (group == null) throw ApiError.notFound('Group not found.');
  return group;
}

Future<Project> _requireProject(StructuredLogDatabase db, int projectId) async {
  final project = await (db.select(
    db.projects,
  )..where((t) => t.id.equals(projectId)))
      .getSingleOrNull();
  if (project == null) throw ApiError.notFound('Project not found.');
  return project;
}

class ProjectRoutes {
  final StructuredLogDatabase _db;
  final Authorizer _authorizer;

  ProjectRoutes(this._db, this._authorizer);

  Router get router => _$ProjectRoutesRouter(this);

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
      final id = await _db.into(_db.projects).insert(
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

    await (_db.update(
      _db.projects,
    )..where((t) => t.id.equals(projectId)))
        .write(companion);

    final updated = await _requireProject(_db, projectId);
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
    )..where((t) => t.projectId.equals(projectId)))
        .getSingleOrNull();

    return jsonOk(
      projectJson(
        project,
        entryCount: usage?.entryCount ?? 0,
        totalBytes: usage?.totalBytes ?? 0,
      ),
    );
  }
}
