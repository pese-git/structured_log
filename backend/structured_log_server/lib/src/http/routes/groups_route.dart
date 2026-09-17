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
import '../../storage/log_filter.dart' show escapeLike;
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
  final AuditWriter _audit;

  GroupRoutes(this._db, this._authorizer, this._audit);

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

    // A transaction for one insert, because the audit record has to be in it:
    // a group that exists without a record of who made it, or a record of a
    // group that does not, are both worse than the request failing
    // (`specs/log-server-audit`).
    final id = await _db.transaction(() async {
      final id =
          await _db.into(_db.groups).insert(GroupsCompanion.insert(name: name));
      await _audit.write(
        action: AuditAction.groupCreated,
        targetType: AuditTargetType.group,
        actorUserId: request.requireUser().userId,
        targetId: id,
        metadata: {'name': name},
      );
      return id;
    });

    final group = await (_db.select(
      _db.groups,
    )..where((t) => t.id.equals(id)))
        .getSingle();
    return jsonOk(groupJson(group), statusCode: 201);
  }

  /// Any authenticated user; results scoped to groups the caller has some
  /// effective role covering (`log-server-rbac`).
  ///
  /// `?name=` narrows to groups whose name contains it (case-insensitive,
  /// `LIKE`) — a picker resolving a group by name (rather than an id no
  /// reader is expected to know) is the only caller so far, but the filter
  /// is general-purpose, not tied to that one screen.
  @Route.get('/v1/groups')
  Future<Response> listGroups(Request request) async {
    final roles = await resolveRoles(_authorizer, request.requireUser());
    final name = request.url.queryParameters['name'];

    final select = _db.select(_db.groups);
    if (name != null && name.isNotEmpty) {
      select.where(
        (t) => t.name.like('%${escapeLike(name)}%', escapeChar: r'\'),
      );
    }
    final groups = await select.get();

    final visible = groups.where(
      (g) => canRead(roles, targetType: ScopeType.group, targetId: g.id),
    );
    return jsonOk({'items': visible.map(groupJson).toList()});
  }
}
