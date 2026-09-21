import 'dart:async';
import 'dart:convert';
import 'dart:typed_data' show BytesBuilder;

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../auth/identity_provider.dart';
import '../../errors.dart';
import '../../live/log_broadcast.dart';
import '../../live/project_directory.dart';
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

/// The SSE frame of an entry, encoded once however many subscriptions deliver
/// it. Every subscription of a group receives the same [LogEntry] object from
/// the broadcast and sends the same bytes (nothing in the frame depends on who
/// is reading), so encoding per subscriber was the same JSON and UTF-8 work
/// repeated once for each of them.
final _encodedEvents = Expando<List<int>>('encoded log events');

List<int> _eventBytes(LogEntry entry) => _encodedEvents[entry] ??= sseEvent(
      id: entry.id,
      event: 'log',
      data: jsonEncode(logEntryJson(entry)),
    );

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

  /// What a subscription asks about a project, shared by every subscription of
  /// this server (`project_directory.dart`). Created on first use, so a
  /// handler that never streams holds no watch on the database.
  late final ProjectDirectory _projects = ProjectDirectory(_db);

  /// The directory, for tests that count how often it went to the database.
  ProjectDirectory get projectDirectory => _projects;

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

    // What is waiting to be written. A batch of entries reaches a subscription
    // within one turn of the event loop, and each `body.add` is a write to the
    // socket — a system call — so ten entries cost ten of them per subscriber.
    // They are collected here and written together once the turn's events have
    // all arrived: the bytes and their order are the same, only the number of
    // writes changes.
    final outbox = <List<int>>[];
    var flushScheduled = false;

    void flush() {
      flushScheduled = false;
      if (outbox.isEmpty) return;
      final chunks = List<List<int>>.of(outbox);
      outbox.clear();
      if (body.isClosed) return;
      if (chunks.length == 1) {
        body.add(chunks.single);
        return;
      }
      final joined = BytesBuilder(copy: false);
      chunks.forEach(joined.add);
      body.add(joined.takeBytes());
    }

    void enqueue(List<int> bytes) {
      outbox.add(bytes);
      if (flushScheduled) return;
      flushScheduled = true;
      // Not a microtask: the broadcast hands a batch over one event per
      // microtask, and a flush queued in between would write each on its own.
      Timer.run(flush);
    }

    Future<void> end(String reason) async {
      // Anything already accepted goes out before the end frame, not after it.
      flush();
      if (!body.isClosed) {
        body.add(sseEnd(reason));
        await body.close();
      }
      await stop();
    }

    var lastDeliveredId = sinceId ?? 0;

    /// Writes [entry] to the stream, unless something newer already went out.
    /// The id is checked here as well as on arrival: a lookup can finish after
    /// a later entry was sent, and an id must never go backwards.
    void send(LogEntry entry) {
      if (entry.id <= lastDeliveredId) return;
      if (body.isClosed) return;
      lastDeliveredId = entry.id;
      enqueue(_eventBytes(entry));
    }

    /// Catch-up delivery: one entry at a time, awaited by the caller, so order
    /// is the caller's.
    Future<void> deliver(LogEntry entry) async {
      if (entry.id <= lastDeliveredId) return;
      if (!filter.matches(entry)) return;
      if (!await _isVisible(entry, scope)) return;
      send(entry);
    }

    // Live delivery. An entry whose project is already known is decided on the
    // spot, with no waiting and no database. One that needs a lookup — the
    // first of a project, or the first after a change — joins a queue, and
    // while that queue is not empty *everything* joins it: an entry decided
    // immediately behind one still waiting would reach the client first, and
    // ids would arrive out of order. The queue is what keeps them in order
    // (it used to be the database's own FIFO, which caching takes away).
    var pending = 0;
    var tail = Future<void>.value();

    void deliverLive(LogEntry entry) {
      if (entry.id <= lastDeliveredId) return;
      if (!filter.matches(entry)) return;

      if (pending == 0) {
        final verdict = _visibleIfKnown(entry, scope);
        if (verdict != null) {
          if (verdict) send(entry);
          return;
        }
      }

      pending++;
      tail = tail.then((_) async {
        try {
          if (await _isVisible(entry, scope)) send(entry);
        } catch (_) {
          // A lookup that failed (the database went away) cannot be told from
          // "not visible"; ending is the safe answer, and nothing awaits this
          // chain to hear about an error.
          await end('server_error');
        } finally {
          pending--;
        }
      });
    }

    body = StreamController<List<int>>(
      onCancel: stop,
    );

    upstream = _broadcast.stream.listen(
      (entry) {
        if (buffering) {
          buffered.add(entry);
          return;
        }
        // The broadcast stream has no back-pressure to apply, so this never
        // waits; `deliverLive` keeps order itself.
        deliverLive(entry);
      },
      // The broadcast closes when the process is shutting down, and this is
      // what lets it. `shelf_io`'s graceful close waits for active
      // connections to finish, and a subscription never finishes on its own:
      // without ending the body here the server sits on SIGTERM until
      // something kills it — which for `docker stop` means ten seconds and
      // then SIGKILL, on a SQLite database mid-write.
      onDone: () => unawaited(end('server_shutdown')),
    );

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
        flush();
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
  /// silently (`log-server-live-stream`). "Right now" is as of the last change
  /// to the `projects` table, which is what [ProjectDirectory] forgets on.
  Future<bool> _isVisible(LogEntry entry, LogScope scope) async {
    if (scope.projectId != null && entry.projectId != scope.projectId) {
      return false;
    }
    final standing = await _projects.standing(entry.projectId);
    return standing != null && _inScope(standing, scope);
  }

  /// [_isVisible] without waiting: the answer if the project's standing is
  /// already known, `null` if it has to be looked up.
  bool? _visibleIfKnown(LogEntry entry, LogScope scope) {
    if (scope.projectId != null && entry.projectId != scope.projectId) {
      return false;
    }
    final standing = _projects.peek(entry.projectId);
    return standing == null ? null : _inScope(standing, scope);
  }

  static bool _inScope(ProjectStanding standing, LogScope scope) {
    if (standing.isBlocked) return false;
    if (scope.groupId != null && standing.groupId != scope.groupId)
      return false;
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
      // Through the directory: every subscription asks this each heartbeat, and
      // the answer is the same one deliveries use.
      final standing = await _projects.standing(projectId);
      if (standing == null || standing.isBlocked) return 'project_blocked';
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
