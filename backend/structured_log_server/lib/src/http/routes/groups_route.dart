import 'package:shelf/shelf.dart';

import '../../auth/identity_provider.dart';
import '../../errors.dart';
import '../../rbac/access_check.dart';
import '../../rbac/authorizer.dart';
import '../../storage/database.dart';
import '../json_response.dart';
import '../principal_middleware.dart';
import '../request_helpers.dart';

Map<String, Object?> groupJson(Group group) {
  return {
    'id': group.id,
    'name': group.name,
    'created_at': toIso8601Utc(group.createdAt),
  };
}

/// `POST /v1/groups` — `admin` only (`log-server-rbac`).
Future<Response> createGroup(
  StructuredLogDatabase db,
  Authorizer authorizer,
  Request request,
) async {
  final roles = await resolveRoles(authorizer, request.requireUser());
  if (!isGlobalAdmin(roles)) throw ApiError.forbidden();

  final body = await readJsonBody(request);
  final name = body['name'];
  if (name is! String || name.isEmpty) {
    throw ApiError.invalidRequest(
      'name is required.',
      details: {'field': 'name', 'reason': 'required'},
    );
  }

  final id =
      await db.into(db.groups).insert(GroupsCompanion.insert(name: name));
  final group = await (db.select(
    db.groups,
  )..where((t) => t.id.equals(id)))
      .getSingle();
  return jsonOk(groupJson(group), statusCode: 201);
}

/// `GET /v1/groups` — any authenticated user; results scoped to groups the
/// caller has some effective role covering (`log-server-rbac`).
Future<Response> listGroups(
  StructuredLogDatabase db,
  Authorizer authorizer,
  Request request,
) async {
  final roles = await resolveRoles(authorizer, request.requireUser());
  final groups = await db.select(db.groups).get();
  final visible = groups.where(
    (g) => canRead(roles, targetType: ScopeType.group, targetId: g.id),
  );
  return jsonOk({'items': visible.map(groupJson).toList()});
}
