import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../auth/identity_provider.dart';
import '../../errors.dart';
import '../../ingest/ingest.dart';
import '../../rbac/access_check.dart';
import '../../rbac/authorizer.dart';
import '../../storage/database.dart';
import '../../storage/log_store.dart';
import '../../storage/query.dart';
import '../json_response.dart';
import '../principal_middleware.dart';

part 'logs_route.g.dart';

/// Default cap on a `POST /v1/logs` request body — a placeholder until
/// `log-server-config` (section 8) makes it a `ServerConfig` field.
const defaultMaxIngestBodyBytes = 10 * 1024 * 1024;

Map<String, Object?> logEntryJson(LogEntry row) {
  final context = jsonDecode(row.contextJson) as Map<String, Object?>;
  return {
    ...context,
    'id': row.id,
    'project_id': row.projectId,
    'received_at': toIso8601Utc(row.receivedAt),
  };
}

class LogRoutes {
  final StructuredLogDatabase _db;
  final Authorizer _authorizer;
  final LogStore _logStore;

  /// Annotated handlers may not take optional parameters, so the ingest body
  /// cap is a field rather than a named argument — it becomes a
  /// `ServerConfig` value in section 8 anyway (`log-server-config`).
  final int maxBodyBytes;

  LogRoutes(
    this._db,
    this._authorizer,
    this._logStore, {
    this.maxBodyBytes = defaultMaxIngestBodyBytes,
  });

  Router get router => _$LogRoutesRouter(this);

  /// Project-secret-key auth, validates and quota-checks each entry
  /// independently, always answers `202` once the request itself is accepted
  /// (`log-server-api`).
  @Route.post('/v1/logs')
  Future<Response> ingestLogs(Request request) async {
    final projectId = request.requireProject();

    final project = await (_db.select(
      _db.projects,
    )..where((t) => t.id.equals(projectId)))
        .getSingleOrNull();
    if (project == null || project.isBlocked) {
      throw const ApiError(
        403,
        'project_blocked',
        'This project is blocked and cannot accept log entries.',
      );
    }

    final raw = await request.readAsString();
    if (utf8.encode(raw).length > maxBodyBytes) {
      throw const ApiError(
        413,
        'payload_too_large',
        'Request body exceeds the configured size limit.',
      );
    }

    final decoded = raw.isEmpty ? <Object?>[] : jsonDecode(raw);
    if (decoded is! List) {
      throw ApiError.invalidRequest('Request body must be a JSON array.');
    }

    final usage = await (_db.select(
      _db.projectUsage,
    )..where((t) => t.projectId.equals(projectId)))
        .getSingleOrNull();

    final outcome = processIngestBatch(
      rawEntries: decoded,
      maxEntries: project.maxEntries,
      maxBytes: project.maxBytes,
      currentEntryCount: usage?.entryCount ?? 0,
      currentTotalBytes: usage?.totalBytes ?? 0,
      receivedAt: DateTime.now(),
    );

    if (outcome.accepted.isNotEmpty) {
      await _db.transaction(() async {
        await _logStore.insertBatch(projectId, outcome.accepted);
        await (_db.update(
          _db.projectUsage,
        )..where((t) => t.projectId.equals(projectId)))
            .write(
          ProjectUsageCompanion.custom(
            entryCount:
                _db.projectUsage.entryCount + Constant(outcome.entryCountDelta),
            totalBytes:
                _db.projectUsage.totalBytes + Constant(outcome.bytesDelta),
          ),
        );
      });
    }

    return jsonOk({
      'accepted': outcome.accepted.length,
      'rejected': outcome.rejected.map((r) => r.toJson()).toList(),
    }, statusCode: 202);
  }

  /// Access-token auth, exactly one of `project_id`/`group_id` required,
  /// RBAC-checked (`log-server-api`, `log-server-rbac`).
  @Route.get('/v1/logs')
  Future<Response> queryLogs(Request request) async {
    final identity = request.requireUser();
    final params = request.url.queryParameters;
    final projectIdParam = params['project_id'];
    final groupIdParam = params['group_id'];
    if ((projectIdParam == null) == (groupIdParam == null)) {
      throw ApiError.invalidRequest(
        'Exactly one of project_id or group_id is required.',
      );
    }

    final roles = await resolveRoles(_authorizer, identity);
    List<int> projectIds;

    if (projectIdParam != null) {
      final projectId = int.tryParse(projectIdParam);
      if (projectId == null) throw ApiError.notFound('project_id not found.');
      final project = await (_db.select(
        _db.projects,
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
        throw const ApiError(
          403,
          'project_blocked',
          'This project is blocked.',
        );
      }
      projectIds = [projectId];
    } else {
      final groupId = int.tryParse(groupIdParam!);
      if (groupId == null) throw ApiError.notFound('group_id not found.');
      final group = await (_db.select(
        _db.groups,
      )..where((t) => t.id.equals(groupId)))
          .getSingleOrNull();
      if (group == null) throw ApiError.notFound('group_id not found.');
      if (!canRead(roles, targetType: ScopeType.group, targetId: groupId)) {
        throw ApiError.forbidden();
      }
      final projects = await (_db.select(
        _db.projects,
      )..where((t) => t.groupId.equals(groupId) & t.isBlocked.equals(false)))
          .get();
      projectIds = projects.map((p) => p.id).toList();
    }

    if (projectIds.isEmpty) {
      return jsonOk({'items': <Object?>[], 'next_cursor': null});
    }

    final connectionGeneration = params['connection_generation'];
    final page = await _logStore.query(
      LogQuery(
        projectIds: projectIds,
        minLevel: params['level'],
        category: params['category'],
        logger: params['logger'],
        from:
            params['from'] != null ? DateTime.tryParse(params['from']!) : null,
        to: params['to'] != null ? DateTime.tryParse(params['to']!) : null,
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
        limit: params['limit'] != null ? int.parse(params['limit']!) : 50,
        cursor:
            params['cursor'] != null ? int.tryParse(params['cursor']!) : null,
      ),
    );

    return jsonOk({
      'items': page.entries.map(logEntryJson).toList(),
      'next_cursor': page.nextCursor?.toString(),
    });
  }

  /// No authentication.
  @Route.get('/healthz')
  Future<Response> healthCheck(Request request) async {
    return jsonOk({'status': 'ok'});
  }
}
