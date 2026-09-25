import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../errors.dart';
import '../../ingest/ingest_coordinator.dart';
import '../../live/log_broadcast.dart';
import '../../rbac/authorizer.dart';
import '../../storage/database.dart';
import '../../storage/log_store.dart';
import '../../storage/query.dart';
import '../json_response.dart';
import '../page_request.dart';
import '../time_range.dart';
import '../log_query_params.dart';
import '../request_helpers.dart';
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
  final LogBroadcast _broadcast;

  /// Annotated handlers may not take optional parameters, so the ingest body
  /// cap is a field rather than a named argument — it becomes a
  /// `ServerConfig` value in section 8 anyway (`log-server-config`).
  final int maxBodyBytes;

  LogRoutes(
    this._db,
    this._authorizer,
    this._logStore,
    this._broadcast, {
    this.maxBodyBytes = defaultMaxIngestBodyBytes,
  });

  late final IngestCoordinator _coordinator = IngestCoordinator(
    _db,
    _logStore,
    _broadcast,
  );

  /// The coordinator, for tests that count how many transactions carried how
  /// many requests.
  IngestCoordinator get ingestCoordinator => _coordinator;

  Router get router => _$LogRoutesRouter(this);

  /// Project-secret-key auth, validates and quota-checks each entry
  /// independently, always answers `202` once the request itself is accepted
  /// (`log-server-api`).
  @Route.post('/v1/logs')
  Future<Response> ingestLogs(Request request) async {
    final projectId = request.requireProject();

    final project = await (_db.select(
      _db.projects,
    )..where((t) => t.id.equals(projectId))).getSingleOrNull();
    if (project == null || project.isBlocked) {
      throw const ApiError(
        403,
        'project_blocked',
        'This project is blocked and cannot accept log entries.',
      );
    }

    final String raw;
    try {
      raw = await readBodyCapped(request, maxBodyBytes);
    } on BodyTooLargeException {
      throw const ApiError(
        413,
        'payload_too_large',
        'Request body exceeds the configured size limit.',
      );
    }

    // Through the helper, so a malformed body is 400 rather than the 500 a
    // bare jsonDecode produced — this endpoint takes whatever a client sends.
    final decoded = await readJsonArrayBody(raw);

    // Stored together with whatever else is arriving (`IngestCoordinator`):
    // usage is read and updated in that transaction, so concurrent batches are
    // judged one after another and cannot together pass a quota that each
    // alone respects (`log-server-quotas`), and the rows are published after
    // the commit.
    final outcome = await _coordinator.submit(
      projectId: projectId,
      maxEntries: project.maxEntries,
      maxBytes: project.maxBytes,
      rawEntries: decoded,
    );

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
    final scope = await resolveLogScope(_db, _authorizer, identity, params);
    final filter = parseLogFilter(params);
    final paging = parsePageRequest(params);
    final range = parseTimeRange(params);

    if (scope.projectIds.isEmpty) {
      return jsonOk({'items': <Object?>[], 'next_cursor': null});
    }

    final page = await _logStore.query(
      LogQuery(
        projectIds: scope.projectIds,
        filter: filter,
        from: range.from,
        to: range.to,
        limit: paging.limit,
        cursor: paging.cursor,
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
