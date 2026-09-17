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

part 'teams_route.g.dart';

Map<String, Object?> teamJson(Team team) {
  return {
    'id': team.id,
    'group_id': team.groupId,
    'name': team.name,
    'created_at': toIso8601Utc(team.createdAt),
  };
}

Future<Group> _requireGroup(StructuredLogDatabase db, int groupId) async {
  final group = await (db.select(
    db.groups,
  )..where((t) => t.id.equals(groupId)))
      .getSingleOrNull();
  if (group == null) throw ApiError.notFound('Group not found.');
  return group;
}

Future<Team> _requireTeam(StructuredLogDatabase db, int teamId) async {
  final team = await (db.select(
    db.teams,
  )..where((t) => t.id.equals(teamId)))
      .getSingleOrNull();
  if (team == null) throw ApiError.notFound('Team not found.');
  return team;
}

class TeamRoutes {
  final StructuredLogDatabase _db;
  final Authorizer _authorizer;
  final AuditWriter _audit;

  TeamRoutes(this._db, this._authorizer, this._audit);

  Router get router => _$TeamRoutesRouter(this);

  /// `owner` of `:groupId`, or `admin` (`log-server-rbac`, decision 6/7 —
  /// a `Team` belongs to exactly one group and only that group's owner, or
  /// `admin`, may create one in it).
  @Route.post('/v1/groups/<groupId>/teams')
  Future<Response> createTeam(Request request, String groupId) async {
    final identity = request.requireUser();
    final group = await _requireGroup(_db, parsePathId(groupId, 'groupId'));

    final roles = await resolveRoles(_authorizer, identity);
    if (!canWrite(roles, targetType: ScopeType.group, targetId: group.id)) {
      throw ApiError.forbidden();
    }

    final body = await readJsonBody(request);
    final name = body['name'];
    if (name is! String || name.isEmpty) {
      throw ApiError.invalidRequest(
        'name is required.',
        details: {'field': 'name', 'reason': 'required'},
      );
    }

    final id = await _db.transaction(() async {
      final id = await _db.into(_db.teams).insert(
            TeamsCompanion.insert(groupId: group.id, name: name),
          );
      await _audit.write(
        action: AuditAction.teamCreated,
        targetType: AuditTargetType.team,
        actorUserId: identity.userId,
        targetId: id,
        metadata: {'name': name, 'group_id': group.id},
      );
      return id;
    });

    final team = await _requireTeam(_db, id);
    return jsonOk(teamJson(team), statusCode: 201);
  }

  /// `owner` of the team's group, or `admin` (`docs/api/http-api.md`).
  /// Bumps `token_version` for the added user only — the rest of the
  /// team's members already have whatever tokens they have, and this new
  /// membership doesn't change what those tokens say (`design.md` decision
  /// 10, which reserves the cascading bulk update for a *team-scoped*
  /// `RoleAssignment` changing, not for the team's own membership; `tasks.md`
  /// 10.2 tests exactly this). Idempotent: adding someone already a member
  /// is not an error — the request's outcome ("this user is in this team")
  /// already holds, and nothing else about the row can differ, since
  /// membership carries no data beyond the pair itself.
  @Route.post('/v1/teams/<teamId>/members')
  Future<Response> addTeamMember(Request request, String teamId) async {
    final identity = request.requireUser();
    final team = await _requireTeam(_db, parsePathId(teamId, 'teamId'));

    final roles = await resolveRoles(_authorizer, identity);
    if (!canWrite(
      roles,
      targetType: ScopeType.group,
      targetId: team.groupId,
    )) {
      throw ApiError.forbidden();
    }

    final body = await readJsonBody(request);
    final userId = body['user_id'];
    if (userId is! int) {
      throw ApiError.invalidRequest(
        'user_id is required.',
        details: {'field': 'user_id', 'reason': 'required'},
      );
    }

    final user = await (_db.select(
      _db.users,
    )..where((t) => t.id.equals(userId)))
        .getSingleOrNull();
    if (user == null) throw ApiError.notFound('User not found.');

    final alreadyMember = await (_db.select(_db.teamMembers)
          ..where(
            (t) => t.teamId.equals(team.id) & t.userId.equals(userId),
          ))
        .getSingleOrNull();
    if (alreadyMember != null) return Response(204);

    await _db.transaction(() async {
      await _db.into(_db.teamMembers).insert(
            TeamMembersCompanion.insert(teamId: team.id, userId: userId),
          );
      await incrementTokenVersion(_db, userId);
      await _audit.write(
        action: AuditAction.teamMemberAdded,
        targetType: AuditTargetType.team,
        actorUserId: identity.userId,
        targetId: team.id,
        metadata: {'user_id': userId},
      );
    });

    return Response(204);
  }

  /// Same rule as adding a member. Bumps `token_version` for the removed
  /// user only, the same single-user reasoning as above — this is the
  /// direction that actually matters for immediate revocation (`tasks.md`
  /// 10.2: the removed member's already-issued token stops working on
  /// their very next request; the remaining members' tokens are untouched).
  @Route.delete('/v1/teams/<teamId>/members/<userId>')
  Future<Response> removeTeamMember(
    Request request,
    String teamId,
    String userId,
  ) async {
    final identity = request.requireUser();
    final team = await _requireTeam(_db, parsePathId(teamId, 'teamId'));
    final removedUserId = parsePathId(userId, 'userId');

    final roles = await resolveRoles(_authorizer, identity);
    if (!canWrite(
      roles,
      targetType: ScopeType.group,
      targetId: team.groupId,
    )) {
      throw ApiError.forbidden();
    }

    final membership = await (_db.select(_db.teamMembers)
          ..where(
            (t) => t.teamId.equals(team.id) & t.userId.equals(removedUserId),
          ))
        .getSingleOrNull();
    if (membership == null) {
      throw ApiError.notFound('This user is not a member of the team.');
    }

    await _db.transaction(() async {
      await (_db.delete(_db.teamMembers)
            ..where(
              (t) => t.teamId.equals(team.id) & t.userId.equals(removedUserId),
            ))
          .go();
      await incrementTokenVersion(_db, removedUserId);
      await _audit.write(
        action: AuditAction.teamMemberRemoved,
        targetType: AuditTargetType.team,
        actorUserId: identity.userId,
        targetId: team.id,
        metadata: {'user_id': removedUserId},
      );
    });

    return Response(204);
  }
}
