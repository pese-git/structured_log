import 'dart:async';
import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../auth/identity_provider.dart';
import '../../errors.dart';
import '../../live/log_broadcast.dart';
import '../../rbac/authorizer.dart';
import '../../storage/database.dart';
import '../../storage/log_store.dart';
import '../../storage/query.dart';
import '../log_query_params.dart';
import '../principal_middleware.dart';
import '../sse.dart';
import 'logs_route.dart' show logEntryJson;

part 'log_stream_route.g.dart';

/// Default gap between keep-alive frames, used when no `ServerConfig` value
/// is supplied (tests, and any caller that hasn't wired configuration yet).
const defaultSseHeartbeat = Duration(seconds: 30);

/// How many entries a single catch-up read pulls at a time
/// (`since_id`) before continuing. Bounded so a client that reconnects with
/// a very old `since_id` can't make the server materialize an unbounded
/// result set in memory.
const _catchUpPageSize = 500;

/// `GET /v1/logs/stream` — Server-Sent Events (`log-server-live-stream`).
class LogStreamRoutes {
  final StructuredLogDatabase _db;
  final Authorizer _authorizer;
  final LogStore _logStore;
  final LogBroadcast _broadcast;
  final IdentityProvider _identityProvider;

  /// Keep-alive interval, which is also the revalidation interval: every
  /// tick both proves the connection is alive and re-checks that the caller
  /// is still allowed to hold it.
  final Duration heartbeatInterval;

  LogStreamRoutes(
    this._db,
    this._authorizer,
    this._logStore,
    this._broadcast,
    this._identityProvider, {
    this.heartbeatInterval = defaultSseHeartbeat,
  });

  Router get router => _$LogStreamRoutesRouter(this);

  /// Subscribes to entries accepted from now on, in the same scope and with
  /// the same filters as `GET /v1/logs`.
  ///
  /// Authorization happens here, before any streaming body exists, so a
  /// rejected caller gets an ordinary JSON 403/404 rather than an
  /// `event-stream` that immediately says no (`log-server-live-stream`).
  @Route.get('/v1/logs/stream')
  Future<Response> streamLogs(Request request) async {
    final identity = request.requireUser();
    final params = request.url.queryParameters;
    final scope = await resolveLogScope(_db, _authorizer, identity, params);
    final filter = parseLogFilter(params);

    final sinceIdParam = params['since_id'];
    int? sinceId;
    if (sinceIdParam != null) {
      sinceId = int.tryParse(sinceIdParam);
      if (sinceId == null) {
        throw ApiError.invalidRequest(
          'since_id must be an integer.',
          details: {'field': 'since_id', 'reason': 'invalid'},
        );
      }
    }

    final accessToken = _bearerToken(request);

    // Subscribe *before* reading history. The buffer below is what closes
    // the gap decision 29 is about: anything committed while the catch-up
    // query runs lands in the buffer instead of falling between the two.
    final buffered = <LogEntry>[];
    var buffering = true;
    late StreamSubscription<LogEntry> upstream;
    Timer? heartbeat;

    late StreamController<List<int>> body;

    Future<void> stop() async {
      heartbeat?.cancel();
      heartbeat = null;
      await upstream.cancel();
    }

    Future<void> end(String reason) async {
      if (!body.isClosed) {
        body.add(sseEnd(reason));
        await body.close();
      }
      await stop();
    }

    var lastDeliveredId = sinceId ?? 0;

    Future<void> deliver(LogEntry entry) async {
      if (entry.id <= lastDeliveredId) return;
      if (!filter.matches(entry)) return;
      if (!await _isVisible(entry, scope)) return;
      if (body.isClosed) return;
      lastDeliveredId = entry.id;
      body.add(
        sseEvent(
          id: entry.id,
          event: 'log',
          data: jsonEncode(logEntryJson(entry)),
        ),
      );
    }

    body = StreamController<List<int>>(
      onCancel: stop,
    );

    upstream = _broadcast.stream.listen((entry) {
      if (buffering) {
        buffered.add(entry);
        return;
      }
      // Fire-and-forget: deliver awaits a point lookup, and the broadcast
      // stream has no back-pressure to apply anyway. Ordering is preserved
      // by the id check inside deliver, not by the await.
      unawaited(deliver(entry));
    });

    // Catch-up, then hand the buffer over. Anything already replayed is
    // dropped by id, so a batch that was both read back and broadcast is
    // delivered exactly once (`log-server-live-stream`).
    unawaited(() async {
      try {
        if (sinceId != null) {
          await _replaySince(sinceId, scope, filter, deliver);
        }
        for (final entry in List<LogEntry>.of(buffered)) {
          await deliver(entry);
        }
        buffered.clear();
        buffering = false;
      } catch (_) {
        await end('server_error');
      }
    }());

    heartbeat = Timer.periodic(heartbeatInterval, (_) async {
      try {
        final reason = await _revalidate(accessToken, scope);
        if (reason != null) {
          await end(reason);
          return;
        }
        if (!body.isClosed) body.add(sseComment());
      } catch (_) {
        // Revalidation couldn't be completed (the database went away, say).
        // A subscription that can no longer be re-checked must not stay
        // open on the strength of its last successful check — and this runs
        // on a timer, where an escaping error would surface as an unhandled
        // asynchronous error rather than as a failed request.
        await end('server_error');
      }
    });

    return Response.ok(
      body.stream,
      headers: sseHeaders,
      // Without this `shelf_io` buffers the streamed body and nothing
      // reaches the client until the buffer fills — for a live stream that
      // means never. In-process handler tests read the stream directly and
      // cannot show it; only a real socket does.
      context: const {'shelf.io.buffer_output': false},
    );
  }

  /// Replays everything with `id > sinceId` that the subscription would have
  /// delivered, oldest first, in bounded pages.
  Future<void> _replaySince(
    int sinceId,
    LogScope scope,
    LogFilter filter,
    Future<void> Function(LogEntry) deliver,
  ) async {
    if (scope.projectIds.isEmpty) return;
    var after = sinceId;
    while (true) {
      final page = await _logStore.query(
        LogQuery(
          projectIds: scope.projectIds,
          filter: filter,
          afterId: after,
          limit: _catchUpPageSize,
        ),
      );
      if (page.entries.isEmpty) return;
      for (final entry in page.entries) {
        await deliver(entry);
      }
      after = page.entries.last.id;
      if (page.entries.length < _catchUpPageSize) return;
    }
  }

  /// Whether [entry] is inside the subscription's scope *right now*.
  ///
  /// Re-checked per entry rather than trusted from subscription time: a
  /// project can be blocked, or added to a subscribed group, while the
  /// connection is open, and a group subscription has to follow both
  /// silently (`log-server-live-stream`).
  Future<bool> _isVisible(LogEntry entry, LogScope scope) async {
    if (scope.projectId != null && entry.projectId != scope.projectId) {
      return false;
    }
    final project = await (_db.select(
      _db.projects,
    )..where((t) => t.id.equals(entry.projectId)))
        .getSingleOrNull();
    if (project == null || project.isBlocked) return false;
    if (scope.groupId != null && project.groupId != scope.groupId) return false;
    return true;
  }

  /// Returns the terminal reason if this subscription may no longer be held,
  /// or `null` if it may.
  ///
  /// Re-verifying the access token is the whole check for the caller:
  /// [IdentityProvider.verifyAccessToken] already rejects a token whose `tv`
  /// no longer matches the stored `token_version`, and every revocation path
  /// (role change, team membership change, deactivation, password change)
  /// bumps that (`log-server-auth`). `is_active`/`deleted_at` are checked on
  /// top of it so the connection doesn't outlive an account that was shut
  /// down without a version bump.
  Future<String?> _revalidate(String? accessToken, LogScope scope) async {
    if (accessToken == null) return 'token_revoked';
    final identity = await _identityProvider.verifyAccessToken(accessToken);
    if (identity == null) return 'token_revoked';

    final user = await (_db.select(
      _db.users,
    )..where((t) => t.id.equals(identity.userId)))
        .getSingleOrNull();
    if (user == null || !user.isActive || user.deletedAt != null) {
      return 'token_revoked';
    }

    // A group subscription silently drops blocked projects instead of
    // ending (that is `_isVisible`'s job); only a direct subscription to a
    // project that got blocked terminates.
    final projectId = scope.projectId;
    if (projectId != null) {
      final project = await (_db.select(
        _db.projects,
      )..where((t) => t.id.equals(projectId)))
          .getSingleOrNull();
      if (project == null || project.isBlocked) return 'project_blocked';
    }

    return null;
  }

  static String? _bearerToken(Request request) {
    final header = request.headers['authorization'];
    const scheme = 'Bearer ';
    if (header == null || !header.startsWith(scheme)) return null;
    return header.substring(scheme.length);
  }
}
