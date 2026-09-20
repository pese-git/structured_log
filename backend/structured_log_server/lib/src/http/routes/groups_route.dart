import 'package:drift/drift.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../audit/audit_action.dart';
import '../../audit/audit_writer.dart';
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

part 'groups_route.g.dart';

/// The `409 sole_group_owner` every action that would leave a group without an
/// owner answers with, whichever action it is — deleting an account, removing
/// a member from the owning team, revoking the owner grant itself.
ApiError soleGroupOwnerError(List<Group> groups, {required String message}) {
  return ApiError(
    409,
    'sole_group_owner',
    message,
    details: {'blocking_groups': groups.map(groupJson).toList()},
  );
}

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
  /// effective role covering (`log-server-rbac`), a page at a time
  /// (`log-server-pagination`), newest first.
  ///
  /// What the caller may see is part of the query, not a filter over its
  /// result: a page of 50 rows of which the caller may see 3 would be empty
  /// in all but name, and its cursor would count rows they cannot see.
  ///
  /// `?name=` narrows to groups whose name contains it (case-insensitive,
  /// `LIKE`) — a picker resolving a group by name (rather than an id no
  /// reader is expected to know) is the only caller so far, but the filter
  /// is general-purpose, not tied to that one screen.
  @Route.get('/v1/groups')
  Future<Response> listGroups(Request request) async {
    final roles = await resolveRoles(_authorizer, request.requireUser());
    final params = request.url.queryParameters;
    final (:limit, :cursor) = parsePageRequest(params);
    final name = params['name'];

    final readable = readableScope(roles);
    if (readable.isEmpty) return jsonOk({'items': [], 'next_cursor': null});

    final select = _db.select(_db.groups)
      ..orderBy([(t) => OrderingTerm.desc(t.id)])
      ..limit(limit + 1);
    if (!readable.everything) {
      select.where((t) => t.id.isIn(readable.groupIds));
    }
    if (cursor != null) {
      select.where((t) => t.id.isSmallerThanValue(cursor));
    }
    if (name != null && name.isNotEmpty) {
      select.where(
        (t) => t.name.like('%${escapeLike(name)}%', escapeChar: r'\'),
      );
    }

    final page = pageFromProbe(await select.get(), limit, (g) => g.id);
    return jsonOk({
      'items': page.items.map(groupJson).toList(),
      'next_cursor': page.nextCursor?.toString(),
    });
  }
}
