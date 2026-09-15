import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:structured_log/structured_log.dart';

import '../../../shared/api/dto/log_dto.dart';
import '../../../shared/api/failure_mapper.dart';
import '../domain/live_feed_event.dart';
import '../domain/log_filter.dart';
import '../domain/log_scope.dart';
import 'log_query_params.dart';

/// `GET /v1/logs/stream`, written by hand on the same `Dio` the typed
/// endpoints use (design.md decision 37).
///
/// Not a `retrofit` interface, and never will be: SSE is one long-lived body
/// parsed frame by frame, not one JSON document, and retrofit's model — a
/// method that returns a deserialized object — cannot describe it. What it
/// does share with the generated clients is the instance it runs on, and so
/// the `Authorization` header and the one-shot refresh that comes with it.
///
/// **Reconnection lives here rather than in the feed.** A dropped socket, an
/// idle connection, a 5xx, and a `token_revoked` that a refresh can fix are
/// all the same thing to the screen — a gap of a second or two — and the
/// server closes the gap itself when the reconnect passes `since_id`
/// (`log-server-live-stream`). Only what reconnecting cannot fix reaches the
/// caller.
class LogStreamClient {
  final Dio _dio;
  final BoundLogger _log;

  /// How long the connection may stay silent before it counts as dead.
  ///
  /// The server sends a keep-alive comment every ~30s (`defaultSseHeartbeat`),
  /// so silence past this is a connection that is open on this side only —
  /// the failure mode a TCP socket does not report. Well above the heartbeat
  /// on purpose: an operator who widened theirs should see a slow feed, not a
  /// reconnect loop.
  final Duration idleTimeout;

  /// First wait after a lost connection; doubles up to [maxBackoff], and
  /// resets as soon as a connection is established.
  final Duration initialBackoff;
  final Duration maxBackoff;

  LogStreamClient(
    this._dio, {
    required BoundLogger logger,
    this.idleTimeout = const Duration(seconds: 90),
    this.initialBackoff = const Duration(seconds: 1),
    this.maxBackoff = const Duration(seconds: 30),
  }) : _log = logger.bind({'category': 'log_stream'});

  /// Subscribes to entries accepted from now on, in [scope] and matching
  /// [filter] — the same ones the list was loaded with.
  ///
  /// [sinceId] is the id of the newest entry already held, so the server
  /// replays what landed between that page and this subscription. Omit it and
  /// the stream starts strictly from now.
  ///
  /// The returned stream is single-subscription: cancelling it closes the
  /// connection and stops reconnecting.
  Stream<LiveFeedEvent> connect({
    required LogScope scope,
    required LogFilter filter,
    int? sinceId,
  }) {
    late StreamController<LiveFeedEvent> controller;

    var stopped = false;
    CancelToken? attempt;
    void Function()? wake;

    /// Waits [delay], or returns early when the subscription is cancelled —
    /// otherwise a feed closed during a 30-second backoff would keep a timer,
    /// and then open a connection nobody is listening to.
    Future<void> sleep(Duration delay) {
      final done = Completer<void>();
      final timer = Timer(delay, () {
        if (!done.isCompleted) done.complete();
      });
      wake = () {
        timer.cancel();
        if (!done.isCompleted) done.complete();
      };
      return done.future;
    }

    Future<void> run() async {
      var lastId = sinceId;
      var backoff = initialBackoff;

      while (!stopped) {
        final token = CancelToken();
        attempt = token;
        var terminal = false;

        try {
          final response = await _dio.get<ResponseBody>(
            '/v1/logs/stream',
            queryParameters: logQueryParameters(
              scope: scope,
              filter: filter,
              sinceId: lastId,
            ),
            cancelToken: token,
            options: Options(
              responseType: ResponseType.stream,
              receiveTimeout: idleTimeout,
              headers: const {'accept': 'text/event-stream'},
            ),
          );
          if (stopped) break;

          // Reset only once a connection actually opened: a server that
          // accepts and immediately drops must still be backed off from.
          backoff = initialBackoff;

          // Set when this connection is finished with, whether or not another
          // one follows.
          var closed = false;

          await for (final frame in parseSseFrames(response.data!.stream)) {
            if (stopped) break;
            switch (frame.event) {
              case 'log':
                final entry = LogEntryDto.fromJson(
                  jsonDecode(frame.data) as Map<String, dynamic>,
                );
                // The frame's own id, falling back to the entry's — they are
                // the same value, and this is what a reconnect resumes from.
                lastId = frame.id ?? entry.id;
                controller.add(LiveFeedEvent.entry(entry));
              case 'end':
                final reason = _reasonOf(frame.data);
                closed = true;
                if (_resolvableByReconnect(reason)) {
                  // Reconnect rather than wait for the server to hang up:
                  // the new request is what gets a 401 the interceptor can
                  // refresh against.
                  _log.info('stream.reopening', context: {'reason': reason});
                } else {
                  _log.warning('stream.ended', context: {'reason': reason});
                  controller.add(LiveFeedEvent.ended(reason));
                  terminal = true;
                }
              default:
                // Unknown event names and bare `data:` frames are ignored
                // rather than refused: the format allows a server to add
                // frames a client is not required to understand.
                break;
            }
            if (closed) break;
          }
        } on DioException catch (error) {
          if (stopped || CancelToken.isCancel(error)) break;
          if (!_isRetryable(error)) {
            _log.warning(
              'stream.refused',
              context: {'status': error.response?.statusCode},
            );
            controller.add(LiveFeedEvent.failed(mapDioException(error)));
            terminal = true;
          } else {
            _log.debug(
              'stream.interrupted',
              context: {'type': error.type.name},
            );
          }
        } finally {
          token.cancel('log stream attempt finished');
        }

        if (terminal || stopped) break;

        await sleep(backoff);
        final doubled = backoff * 2;
        backoff = doubled > maxBackoff ? maxBackoff : doubled;
      }

      if (!controller.isClosed) await controller.close();
    }

    controller = StreamController<LiveFeedEvent>(
      onListen: () => unawaited(run()),
      onCancel: () {
        stopped = true;
        wake?.call();
        attempt?.cancel('log feed closed');
      },
    );
    return controller.stream;
  }

  /// Whether losing the connection this way is worth another attempt.
  ///
  /// A 401 never gets here in the ordinary case — the interceptor renews the
  /// token and replays the request — so one that does means the session is
  /// finished, and retrying it would only ask again with the same answer.
  static bool _isRetryable(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
      case DioExceptionType.unknown:
        return true;
      case DioExceptionType.cancel:
      case DioExceptionType.badCertificate:
        return false;
      case DioExceptionType.badResponse:
        final status = error.response?.statusCode ?? 0;
        return status >= 500 || status == 429;
    }
  }

  /// Whether an `event: end` is something a new connection settles.
  ///
  /// `token_revoked` is: the reconnect goes out with the stored access token,
  /// the server answers 401 to the request itself, and the interceptor's
  /// refresh-and-replay takes over — the same path any other request follows
  /// (`specs/admin-client-auth`). If the refresh fails too, the session ends
  /// there rather than here.
  ///
  /// `server_shutdown` is too: the server is being restarted, which is what a
  /// deploy looks like from here, and the feed should pick up again on its own
  /// once it is back rather than make the reader reload the page.
  ///
  /// Anything unrecognised is treated as final. A reason this client does not
  /// know is a reason it cannot claim to have handled, and a feed that stops
  /// visibly is better than one that reconnects forever.
  static bool _resolvableByReconnect(String reason) =>
      reason == 'token_revoked' ||
      reason == 'server_error' ||
      reason == 'server_shutdown';

  static String _reasonOf(String data) {
    try {
      final decoded = jsonDecode(data);
      if (decoded is Map<String, dynamic>) {
        return decoded['reason'] as String? ?? 'unknown';
      }
    } on FormatException {
      // A terminal frame we cannot read is still terminal.
    }
    return 'unknown';
  }
}

/// One `data:`-carrying SSE frame.
class SseFrame {
  final int? id;
  final String? event;
  final String data;

  const SseFrame({this.id, this.event, required this.data});
}

/// Splits an SSE body into frames.
///
/// Public for its tests: frame assembly is the part most likely to be wrong
/// in ways no widget test would show — a payload split across two TCP chunks,
/// a `data:` value that itself contains newlines, a keep-alive comment
/// arriving mid-frame.
Stream<SseFrame> parseSseFrames(Stream<List<int>> bytes) async* {
  int? id;
  String? event;
  final data = StringBuffer();
  var hasData = false;

  void reset() {
    id = null;
    event = null;
    data.clear();
    hasData = false;
  }

  // The UTF-8 decoder is what makes a chunk boundary in the middle of a
  // multi-byte character harmless; LineSplitter handles both `\n` and `\r\n`.
  // `bind`, not `transform`: the body arrives as a `Stream<Uint8List>`, and
  // `transform` is typed on the stream's own reified element type — handing a
  // `List<int>` converter to one throws at runtime rather than at compile
  // time.
  final lines = const LineSplitter().bind(
    const Utf8Decoder(allowMalformed: true).bind(bytes),
  );

  await for (final line in lines) {
    if (line.isEmpty) {
      if (hasData || event != null) {
        yield SseFrame(id: id, event: event, data: data.toString());
      }
      reset();
      continue;
    }
    // A comment — the keep-alive frame. It carries no field and exists only
    // to prove the connection is alive.
    if (line.startsWith(':')) continue;

    final colon = line.indexOf(':');
    final field = colon == -1 ? line : line.substring(0, colon);
    var value = colon == -1 ? '' : line.substring(colon + 1);
    if (value.startsWith(' ')) value = value.substring(1);

    switch (field) {
      case 'id':
        id = int.tryParse(value);
      case 'event':
        event = value;
      case 'data':
        if (hasData) data.write('\n');
        data.write(value);
        hasData = true;
      default:
        // `retry:` and anything else the format may grow.
        break;
    }
  }
}
