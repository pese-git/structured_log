import 'package:drift/drift.dart';
import 'package:shelf/shelf.dart';

import '../../auth/identity_provider.dart';
import '../../errors.dart';
import '../../rbac/access_check.dart';
import '../../rbac/authorizer.dart';
import '../../storage/database.dart';
import '../auth_middleware.dart';
import '../json_response.dart';
import '../request_helpers.dart';

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

/// `POST /v1/groups/:groupId/projects` — `owner` of `:groupId`, or `admin`
/// (`log-server-rbac`, `log-server-quotas`).
Future<Response> createProject(
  StructuredLogDatabase db,
  Authorizer authorizer,
  Request request,
) async {
  final groupId = requirePathParamInt(request, 'groupId');
  await _requireGroup(db, groupId);

  final roles = await resolveRoles(authorizer, request.verifiedIdentity);
  if (!canWrite(roles, targetType: ScopeType.group, targetId: groupId)) {
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

  final projectId = await db.transaction(() async {
    final id = await db.into(db.projects).insert(
          ProjectsCompanion.insert(
            groupId: groupId,
            name: name,
            retentionDays: retentionDays,
            maxEntries: Value(maxEntries as int?),
            maxBytes: Value(maxBytes as int?),
          ),
        );
    await db
        .into(db.projectUsage)
        .insert(ProjectUsageCompanion.insert(projectId: Value(id)));
    return id;
  });

  final project = await _requireProject(db, projectId);
  return jsonOk(projectJson(project), statusCode: 201);
}

/// `PATCH /v1/projects/:id` — `owner`/`admin` (`log-server-quotas`).
Future<Response> updateProjectQuota(
  StructuredLogDatabase db,
  Authorizer authorizer,
  Request request,
) async {
  final projectId = requirePathParamInt(request, 'id');
  final project = await _requireProject(db, projectId);

  final roles = await resolveRoles(authorizer, request.verifiedIdentity);
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

  await (db.update(
    db.projects,
  )..where((t) => t.id.equals(projectId)))
      .write(companion);

  final updated = await _requireProject(db, projectId);
  return jsonOk(projectJson(updated));
}

/// `GET /v1/projects/:id` — `owner`/`user` with access, or `admin`; includes
/// `entry_count`/`total_bytes` (`design.md` decision 22).
Future<Response> getProject(
  StructuredLogDatabase db,
  Authorizer authorizer,
  Request request,
) async {
  final projectId = requirePathParamInt(request, 'id');
  final project = await _requireProject(db, projectId);

  final roles = await resolveRoles(authorizer, request.verifiedIdentity);
  if (!canRead(
    roles,
    targetType: ScopeType.project,
    targetId: projectId,
    enclosingGroupId: project.groupId,
  )) {
    throw ApiError.forbidden();
  }

  final usage = await (db.select(
    db.projectUsage,
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
