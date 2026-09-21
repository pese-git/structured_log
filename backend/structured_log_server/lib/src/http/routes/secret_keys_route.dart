import 'package:drift/drift.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../audit/audit_action.dart';
import '../../audit/audit_writer.dart';
import '../../auth/hashing.dart';
import '../../auth/identity_provider.dart';
import '../../errors.dart';
import '../../rbac/access_check.dart';
import '../../rbac/authorizer.dart';
import '../../storage/database.dart';
import '../json_response.dart';
import '../principal_middleware.dart';
import '../request_helpers.dart';

part 'secret_keys_route.g.dart';

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
  )..where((t) => t.id.equals(projectId))).getSingleOrNull();
  if (project == null) throw ApiError.notFound('Project not found.');
  return project;
}

class SecretKeyRoutes {
  final StructuredLogDatabase _db;
  final Authorizer _authorizer;
  final AuditWriter _audit;

  SecretKeyRoutes(this._db, this._authorizer, this._audit);

  Router get router => _$SecretKeyRoutesRouter(this);

  /// `owner`/`admin` (`log-server-auth`, `log-server-rbac`). The plaintext
  /// key is only ever returned here.
  @Route.post('/v1/projects/<id>/secret-keys')
  Future<Response> createSecretKey(Request request, String id) async {
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
    final label = body['label'];
    if (label != null && label is! String) {
      throw ApiError.invalidRequest(
        'label must be a string.',
        details: {'field': 'label', 'reason': 'invalid'},
      );
    }

    final plainKey = generateProjectSecretKey();
    final keyId = await _db.transaction(() async {
      final keyId = await _db
          .into(_db.projectSecretKeys)
          .insert(
            ProjectSecretKeysCompanion.insert(
              projectId: projectId,
              keyHash: hashToken(plainKey),
              label: Value(label as String?),
            ),
          );
      // The label and the project, and nothing else. Neither the key nor its
      // hash goes in an audit record: the journal is read by more people, and
      // for longer, than the response that carries the key once
      // (`specs/log-server-audit`).
      await _audit.write(
        action: AuditAction.secretKeyCreated,
        targetType: AuditTargetType.secretKey,
        actorUserId: identity.userId,
        targetId: keyId,
        metadata: {'project_id': projectId, 'label': label},
      );
      return keyId;
    });

    final row = await (_db.select(
      _db.projectSecretKeys,
    )..where((t) => t.id.equals(keyId))).getSingle();
    return jsonOk(secretKeyJson(row, secret: plainKey), statusCode: 201);
  }

  /// Metadata only, never `secret`.
  @Route.get('/v1/projects/<id>/secret-keys')
  Future<Response> listSecretKeys(Request request, String id) async {
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

    final rows = await (_db.select(
      _db.projectSecretKeys,
    )..where((t) => t.projectId.equals(projectId))).get();
    return jsonOk({'items': rows.map(secretKeyJson).toList()});
  }

  /// `owner`/`admin`, irreversible.
  @Route.delete('/v1/projects/<id>/secret-keys/<keyId>')
  Future<Response> revokeSecretKey(
    Request request,
    String id,
    String keyId,
  ) async {
    final identity = request.requireUser();
    final projectId = parsePathId(id, 'id');
    final secretKeyId = parsePathId(keyId, 'keyId');
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

    final key =
        await (_db.select(_db.projectSecretKeys)..where(
              (t) => t.id.equals(secretKeyId) & t.projectId.equals(projectId),
            ))
            .getSingleOrNull();
    if (key == null) throw ApiError.notFound('Secret key not found.');

    await _db.transaction(() async {
      await (_db.update(_db.projectSecretKeys)
            ..where((t) => t.id.equals(secretKeyId)))
          .write(ProjectSecretKeysCompanion(revokedAt: Value(DateTime.now())));
      await _audit.write(
        action: AuditAction.secretKeyRevoked,
        targetType: AuditTargetType.secretKey,
        actorUserId: identity.userId,
        targetId: secretKeyId,
        metadata: {'project_id': projectId, 'label': key.label},
      );
    });

    return Response(204);
  }
}
