import 'package:drift/drift.dart';

import '../auth/identity_provider.dart';
import '../errors.dart';
import '../rbac/access_check.dart';
import '../rbac/authorizer.dart';
import '../storage/database.dart';
import '../storage/log_filter.dart';

/// The scope a log request addresses, after authorization.
///
/// [projectIds] is what may actually be read: for a group request, blocked
/// projects are already excluded. [projectId]/[groupId] record which of the
/// two forms the caller used — the live stream needs to know, because a
/// project blocked while a direct subscription is open terminates it, while
/// the same project blocked under a group subscription merely drops out
/// (`log-server-live-stream`).
typedef LogScope = ({List<int> projectIds, int? projectId, int? groupId});

/// Parses the filter parameters shared by `GET /v1/logs` and
/// `GET /v1/logs/stream` (`log-server-api`, `log-server-live-stream`: the
/// stream takes the same filters as the historical query).
///
/// An unrecognized `level` is a `400`: it can only be a caller mistake, and
/// silently treating it as "no filter" would hand back entries the caller
/// explicitly asked to exclude.
LogFilter parseLogFilter(Map<String, String> params) {
  final level = params['level'];
  if (level != null && !LogFilter.isValidLevel(level)) {
    throw ApiError.invalidRequest(
      'level must be one of ${logLevelOrder.join(', ')}.',
      details: {'field': 'level', 'reason': 'invalid'},
    );
  }

  final connectionGeneration = params['connection_generation'];
  return LogFilter(
    minLevel: level,
    category: params['category'],
    logger: params['logger'],
    sessionId: params['session_id'],
    requestId: params['request_id'],
    connectionGeneration: connectionGeneration != null
        ? int.tryParse(connectionGeneration)
        : null,
    toolCallId: params['tool_call_id'],
    messageId: params['message_id'],
    operationId: params['operation_id'],
    q: params['q'],
    contextEquals: {
      for (final entry in params.entries)
        if (entry.key.startsWith('context.'))
          entry.key.substring('context.'.length): entry.value,
    },
  );
}

/// Resolves and authorizes `project_id`/`group_id` for a log read
/// (`log-server-api`, `log-server-rbac`).
///
/// Shared by `GET /v1/logs` and `GET /v1/logs/stream` so the stream cannot
/// end up with a different notion of who may see what: 404 for a scope that
/// doesn't exist, 403 without a covering role, `403 project_blocked` for a
/// directly requested blocked project, and silent exclusion of blocked
/// projects inside a requested group.
Future<LogScope> resolveLogScope(
  StructuredLogDatabase db,
  Authorizer authorizer,
  VerifiedIdentity identity,
  Map<String, String> params,
) async {
  final projectIdParam = params['project_id'];
  final groupIdParam = params['group_id'];
  if ((projectIdParam == null) == (groupIdParam == null)) {
    throw ApiError.invalidRequest(
      'Exactly one of project_id or group_id is required.',
    );
  }

  final roles = await resolveRoles(authorizer, identity);

  if (projectIdParam != null) {
    final projectId = int.tryParse(projectIdParam);
    if (projectId == null) throw ApiError.notFound('project_id not found.');
    final project = await (db.select(
      db.projects,
    )..where((t) => t.id.equals(projectId)))
        .getSingleOrNull();
    if (project == null) throw ApiError.notFound('project_id not found.');
    if (!canRead(
      roles,
      targetType: ScopeType.project,
      targetId: projectId,
      enclosingGroupId: project.groupId,
    )) {
      throw ApiError.forbidden();
    }
    if (project.isBlocked) {
      throw const ApiError(403, 'project_blocked', 'This project is blocked.');
    }
    return (projectIds: [projectId], projectId: projectId, groupId: null);
  }

  final groupId = int.tryParse(groupIdParam!);
  if (groupId == null) throw ApiError.notFound('group_id not found.');
  final group = await (db.select(
    db.groups,
  )..where((t) => t.id.equals(groupId)))
      .getSingleOrNull();
  if (group == null) throw ApiError.notFound('group_id not found.');
  if (!canRead(roles, targetType: ScopeType.group, targetId: groupId)) {
    throw ApiError.forbidden();
  }
  final projects = await (db.select(
    db.projects,
  )..where((t) => t.groupId.equals(groupId) & t.isBlocked.equals(false)))
      .get();
  return (
    projectIds: projects.map((p) => p.id).toList(),
    projectId: null,
    groupId: groupId,
  );
}
