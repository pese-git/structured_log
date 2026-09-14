import 'package:drift/drift.dart';
import 'package:shelf/shelf.dart';

import '../../auth/hashing.dart';
import '../../auth/identity_provider.dart';
import '../../errors.dart';
import '../../rbac/access_check.dart';
import '../../rbac/authorizer.dart';
import '../../storage/database.dart';
import '../auth_middleware.dart';
import '../json_response.dart';
import '../request_helpers.dart';

Map<String, Object?> secretKeyJson(ProjectSecretKey key, {String? secret}) {
  final json = <String, Object?>{
    'id': key.id,
    'project_id': key.projectId,
    'label': key.label,
    'created_at': toIso8601Utc(key.createdAt),
    'revoked_at': toIso8601Utc(key.revokedAt),
  };
  if (secret != null) json['secret'] = secret;
  return json;
}

Future<Project> _requireProject(StructuredLogDatabase db, int projectId) async {
  final project = await (db.select(
    db.projects,
  )..where((t) => t.id.equals(projectId)))
      .getSingleOrNull();
  if (project == null) throw ApiError.notFound('Project not found.');
  return project;
}

/// `POST /v1/projects/:id/secret-keys` — `owner`/`admin` (`log-server-auth`,
/// `log-server-rbac`). The plaintext key is only ever returned here.
Future<Response> createSecretKey(
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
  final label = body['label'];
  if (label != null && label is! String) {
    throw ApiError.invalidRequest(
      'label must be a string.',
      details: {'field': 'label', 'reason': 'invalid'},
    );
  }

  final plainKey = generateRandomToken();
  final id = await db.into(db.projectSecretKeys).insert(
        ProjectSecretKeysCompanion.insert(
          projectId: projectId,
          keyHash: hashToken(plainKey),
          label: Value(label as String?),
        ),
      );

  final row = await (db.select(
    db.projectSecretKeys,
  )..where((t) => t.id.equals(id)))
      .getSingle();
  return jsonOk(secretKeyJson(row, secret: plainKey), statusCode: 201);
}

/// `GET /v1/projects/:id/secret-keys` — metadata only, never `secret`.
Future<Response> listSecretKeys(
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

  final rows = await (db.select(
    db.projectSecretKeys,
  )..where((t) => t.projectId.equals(projectId)))
      .get();
  return jsonOk({'items': rows.map(secretKeyJson).toList()});
}

/// `DELETE /v1/projects/:id/secret-keys/:keyId` — `owner`/`admin`,
/// irreversible.
Future<Response> revokeSecretKey(
  StructuredLogDatabase db,
  Authorizer authorizer,
  Request request,
) async {
  final projectId = requirePathParamInt(request, 'id');
  final keyId = requirePathParamInt(request, 'keyId');
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

  final key = await (db.select(db.projectSecretKeys)
        ..where(
          (t) => t.id.equals(keyId) & t.projectId.equals(projectId),
        ))
      .getSingleOrNull();
  if (key == null) throw ApiError.notFound('Secret key not found.');

  await (db.update(
    db.projectSecretKeys,
  )..where((t) => t.id.equals(keyId)))
      .write(
    ProjectSecretKeysCompanion(revokedAt: Value(DateTime.now())),
  );

  return Response(204);
}
