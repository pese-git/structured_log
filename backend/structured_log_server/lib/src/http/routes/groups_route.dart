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

part 'groups_route.g.dart';

Map<String, Object?> groupJson(Group group) {
  return {
    'id': group.id,
    'name': group.name,
    'created_at': toIso8601Utc(group.createdAt),
  };
}

class GroupRoutes {
  final StructuredLogDatabase _db;
  final Authorizer _authorizer;

  GroupRoutes(this._db, this._authorizer);

  Router get router => _$GroupRoutesRouter(this);

  /// `admin` only (`log-server-rbac`).
  @Route.post('/v1/groups')
  Future<Response> createGroup(Request request) async {
    final roles = await resolveRoles(_authorizer, request.requireUser());
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
        await _db.into(_db.groups).insert(GroupsCompanion.insert(name: name));
    final group = await (_db.select(
      _db.groups,
    )..where((t) => t.id.equals(id)))
        .getSingle();
    return jsonOk(groupJson(group), statusCode: 201);
  }

  /// Any authenticated user; results scoped to groups the caller has some
  /// effective role covering (`log-server-rbac`).
  @Route.get('/v1/groups')
  Future<Response> listGroups(Request request) async {
    final roles = await resolveRoles(_authorizer, request.requireUser());
    final groups = await _db.select(_db.groups).get();
    final visible = groups.where(
      (g) => canRead(roles, targetType: ScopeType.group, targetId: g.id),
    );
    return jsonOk({'items': visible.map(groupJson).toList()});
  }
}
