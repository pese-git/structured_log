import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:structured_log/structured_log.dart';

/// Sends a batch of already-encoded entries somewhere, answering the way
/// `POST /v1/logs` does.
///
/// The seam exists so tests can drive the retry and buffering behaviour
/// without a socket — the real implementation is [_HttpBatchSender], and
/// nothing outside this library needs to supply another.
typedef BatchSender = Future<BatchResult> Function(
  List<Map<String, dynamic>> entries,
);

/// What one delivery attempt concluded.
///
/// The distinction that matters is not success versus failure but
/// *retryable* versus not: a 401 from a revoked key will answer 401 forever,
/// while a connection refused may well not.
class BatchResult {
  final bool delivered;
  final bool retryable;
  final String? error;

  /// What `Retry-After` named, when the answer carried one and it pointed
  /// at the future. Null means nothing was said — not that zero was.
  final Duration? retryAfter;

  const BatchResult.delivered()
      : delivered = true,
        retryable = false,
        error = null,
        retryAfter = null;

  /// The server may yet accept this batch — a network failure, a timeout, or
  /// a 5xx.
  const BatchResult.retryable(String this.error, {this.retryAfter})
      : delivered = false,
        retryable = true;

  /// The server rejected the batch and will keep rejecting it — a 4xx.
  const BatchResult.rejected(String this.error)
      : delivered = false,
        retryable = false,
        retryAfter = null;
}

/// A [structured_log] sink that ships entries to a `structured_log_server`
/// over HTTP (`structured-log-http-sender`).
///
/// Plugs in wherever an `OutputFunction` is expected, because it *is* one —
/// calling the instance enqueues an entry and returns immediately, so a slow
/// or unreachable server never blocks the code that logged:
///
/// ```dart
/// final output = HttpLogOutput(
///   serverUrl: 'https://logs.example.com',
///   projectSecretKey: 'slk_...',
/// );
/// StructlogConfiguration.configure(
///   sinks: [LogSink(name: 'server', output: output)],
/// );
///
/// getLogger().info('startup');
/// await output.flushed; // before the process exits
/// ```
///
/// Entries accumulate until [batchSize] of them are waiting or
/// [batchTimeout] elapses, whichever comes first, and then travel as one
/// `POST /v1/logs`. Sends are serialized through a single chained future the
/// way `AsyncFileOutput` serializes writes, so two batches are never in
/// flight at once and their order is the order they were logged in.
class HttpLogOutput {
  /// Base URL of the server; `/v1/logs` is appended.
  final String serverUrl;

  /// Sent as `Authorization: Bearer <projectSecretKey>` on every request.
  final String projectSecretKey;

  /// Entries that trigger a send without waiting for [batchTimeout].
  final int batchSize;

  /// How long a partial batch waits before going out anyway.
  final Duration batchTimeout;

  /// How many entries may wait in memory. Past this the oldest are dropped —
  /// an unreachable server must not turn into unbounded memory growth.
  final int maxBufferedEntries;

  /// Attempts per batch, including the first. Only retryable outcomes are
  /// retried.
  final int maxAttempts;

  /// Delay before the second attempt; doubles for each attempt after that.
  final Duration retryBackoff;

  /// Ceiling on a `Retry-After` this sink will honour. A longer one is
  /// clamped to this and reported, and [Duration.zero] switches honouring
  /// off entirely — the backoff then stands as it did before.
  ///
  /// A ceiling is needed because the header does not come from the log
  /// server: `POST /v1/logs` is deliberately absent from its throttled
  /// endpoints, so a `429` here was written by whatever sits in front of it,
  /// and a misconfigured proxy answering `Retry-After: 86400` would
  /// otherwise silence the sink for a day while the buffer evicted its way
  /// through the outage.
  final Duration maxRetryAfter;

  /// How long one HTTP attempt may take before it counts as a retryable
  /// failure.
  final Duration requestTimeout;

  final BatchSender _send;

  /// The transport this instance created, if it created one — [close] has to
  /// release it, and a caller-supplied [BatchSender] is not ours to close.
  final _HttpBatchSender? _ownedSender;
  final void Function(String message) _report;

  /// Every entry that has not been handed to a delivery attempt yet. This
  /// is the *only* place unsent entries accumulate, which is what makes
  /// [maxBufferedEntries] an actual bound: an earlier design chained one
  /// future per batch, so a long outage grew memory without limit through
  /// the pending chain while the buffer itself looked bounded.
  final Queue<Map<String, dynamic>> _buffer = Queue();
  Timer? _timer;

  /// The moment before which nothing may go out, named by a `Retry-After`
  /// on a refusal.
  ///
  /// It gates the *pump*, not the batch that was refused: a limiter saying
  /// "not before T" is talking about the connection, and honouring it per
  /// batch would leave the sender hammering anyway — a refused batch
  /// exhausts its attempts, gives up, and the next one starts over at once.
  DateTime? _quietUntil;
  Timer? _quietTimer;
  Completer<void>? _quietWake;

  /// Whether the current episode of clamping has been announced, on the
  /// same reasoning as [_overflowAnnounced]: a server stuck on a long
  /// `Retry-After` would otherwise fill the console per batch.
  var _clampAnnounced = false;

  /// At most one pump runs at a time, so batches never overlap and their
  /// order is the order entries were logged in.
  var _pumping = false;
  Future<void>? _pumpDone;
  var _closed = false;

  /// Entries dropped since the buffer last drained, and whether the current
  /// overflow episode has been announced. Reporting every single eviction
  /// would bury the console under exactly the conditions — a server that is
  /// down — when the operator most needs to read it, so an episode is
  /// announced once when it starts and summed up once when it ends.
  var _dropped = 0;
  var _overflowAnnounced = false;

  /// A [sender] replaces the HTTP transport entirely — it exists so the
  /// batching, retry and eviction behaviour can be driven in tests without a
  /// socket, and a caller who supplies one owns its lifetime.
  factory HttpLogOutput({
    required String serverUrl,
    required String projectSecretKey,
    int batchSize = 50,
    Duration batchTimeout = const Duration(seconds: 5),
    int maxBufferedEntries = 10000,
    int maxAttempts = 4,
    Duration retryBackoff = const Duration(milliseconds: 500),
    Duration maxRetryAfter = const Duration(minutes: 5),
    Duration requestTimeout = const Duration(seconds: 30),
    BatchSender? sender,
    void Function(String message)? report,
  }) =>
      HttpLogOutput._(
        serverUrl: serverUrl,
        projectSecretKey: projectSecretKey,
        batchSize: batchSize,
        batchTimeout: batchTimeout,
        maxBufferedEntries: maxBufferedEntries,
        maxAttempts: maxAttempts,
        retryBackoff: retryBackoff,
        maxRetryAfter: maxRetryAfter,
        requestTimeout: requestTimeout,
        report: report,
        ownedSender: sender != null
            ? null
            : _HttpBatchSender(
                endpoint: _logsEndpoint(serverUrl),
                projectSecretKey: projectSecretKey,
                timeout: requestTimeout,
              ),
        sender: sender,
      );

  HttpLogOutput._({
    required this.serverUrl,
    required this.projectSecretKey,
    required this.batchSize,
    required this.batchTimeout,
    required this.maxBufferedEntries,
    required this.maxAttempts,
    required this.retryBackoff,
    required this.maxRetryAfter,
    required this.requestTimeout,
    required _HttpBatchSender? ownedSender,
    required BatchSender? sender,
    required void Function(String message)? report,
  })  : _ownedSender = ownedSender,
        _send = sender ?? ownedSender!.send,
        _report = report ?? _reportToStderr {
    if (batchSize < 1) {
      throw ArgumentError.value(batchSize, 'batchSize', 'must be at least 1');
    }
    if (maxBufferedEntries < batchSize) {
      throw ArgumentError.value(
        maxBufferedEntries,
        'maxBufferedEntries',
        'must be at least batchSize ($batchSize), or a full batch could '
            'never be assembled',
      );
    }
    if (maxAttempts < 1) {
      throw ArgumentError.value(
        maxAttempts,
        'maxAttempts',
        'must be at least 1',
      );
    }
  }

  static Uri _logsEndpoint(String serverUrl) {
    final base = Uri.parse(serverUrl);
    final path = base.path.endsWith('/')
        ? '${base.path}v1/logs'
        : '${base.path}/v1/logs';
    return base.replace(path: path);
  }

  static void _reportToStderr(String message) {
    stderr.writeln('structured_log_http: $message');
  }

  /// Enqueues [entry]. Returns immediately — this is the whole point of the
  /// sink, and the reason [flushed] exists.
  void call(Map<String, dynamic> entry, LogLevel level) {
    if (_closed) {
      _report('dropped an entry logged after close()');
      return;
    }

    _buffer.add(entry);
    while (_buffer.length > maxBufferedEntries) {
      _buffer.removeFirst();
      _dropped++;
      if (!_overflowAnnounced) {
        _overflowAnnounced = true;
        _report(
          'buffer full at $maxBufferedEntries entries — dropping the oldest '
          'unsent entries until the server catches up',
        );
      }
    }

    if (_buffer.length >= batchSize) {
      _startPump();
    } else {
      _timer ??= Timer(batchTimeout, _startPump);
    }
  }

  /// Completes once everything enqueued before this call has been delivered
  /// or definitively given up on (retries exhausted, or a non-retryable
  /// answer). Await it before the process exits.
  Future<void> get flushed {
    _startPump();
    return _pumpDone ?? Future<void>.value();
  }

  /// Stops accepting entries, sends whatever is buffered, and releases the
  /// HTTP client. Later calls are reported and discarded rather than
  /// silently swallowed.
  Future<void> close() async {
    _closed = true;
    // A wait named by the server can outlive the process that owes it. Wake
    // the pump so it can abandon what it is holding rather than hang the
    // shutdown — and cancel the timer, which would keep the isolate alive
    // on its own.
    _wakeFromQuietPeriod();
    await flushed;
    _ownedSender?.close();
  }

  void _wakeFromQuietPeriod() {
    _quietTimer?.cancel();
    _quietTimer = null;
    final wake = _quietWake;
    _quietWake = null;
    if (wake != null && !wake.isCompleted) wake.complete();
  }

  /// Waits out the moment a refusal named. Answers `false` when the wait was
  /// abandoned because the sink is closing — the caller then drops what it
  /// holds rather than send before a server said it could.
  Future<bool> _passQuietPeriod() async {
    final until = _quietUntil;
    if (until == null) return true;
    if (!DateTime.now().isBefore(until)) return true;
    if (_closed) return false;

    final wake = Completer<void>();
    _quietWake = wake;
    _quietTimer = Timer(until.difference(DateTime.now()), () {
      if (!wake.isCompleted) wake.complete();
    });
    await wake.future;
    _wakeFromQuietPeriod();
    return !_closed || !DateTime.now().isBefore(until);
  }

  /// How long to actually wait for a [asked] the server named — [maxRetryAfter]
  /// at most, and `null` when there is nothing to act on.
  ///
  /// A header naming zero or a moment already past says nothing this sink can
  /// use, so the backoff stands rather than collapsing to an immediate retry.
  Duration? _quietPeriodFor(Duration? asked) {
    if (asked == null || asked <= Duration.zero) return null;
    if (maxRetryAfter <= Duration.zero) return null;
    if (asked <= maxRetryAfter) return asked;
    if (!_clampAnnounced) {
      _clampAnnounced = true;
      _report(
        'the server asked to wait ${_seconds(asked)} before sending again; '
        'waiting ${_seconds(maxRetryAfter)} instead (maxRetryAfter)',
      );
    }
    return maxRetryAfter;
  }

  static String _seconds(Duration d) =>
      '${(d.inMilliseconds / 1000).toStringAsFixed(1)}s';

  void _startPump() {
    _timer?.cancel();
    _timer = null;
    if (_pumping || _buffer.isEmpty) return;
    _pumping = true;
    _pumpDone = _pump();
  }

  /// Drains the buffer a batch at a time until nothing is left.
  ///
  /// The loop re-checks the buffer after every delivery, so entries logged
  /// while a batch was in flight are picked up by the same pump. The final
  /// check and clearing [_pumping] happen without an await between them, so
  /// a `call()` cannot slip in and find the pump neither running nor about
  /// to run.
  Future<void> _pump() async {
    try {
      while (_buffer.isNotEmpty) {
        if (_dropped > 0) {
          _report('dropped $_dropped entries while the buffer was full');
          _dropped = 0;
          _overflowAnnounced = false;
        }

        final take = _buffer.length < batchSize ? _buffer.length : batchSize;
        final batch = <Map<String, dynamic>>[
          for (var i = 0; i < take; i++) _buffer.removeFirst(),
        ];

        var carryOn = true;
        try {
          carryOn = await _deliver(batch);
        } catch (error, stackTrace) {
          // One batch that blew up must not stop the ones behind it — the
          // same failure isolation `_SerializedAsyncOutput` applies per
          // write in structured_log.
          _report('sending a batch threw: $error\n$stackTrace');
        }

        if (!carryOn) {
          final abandoned = batch.length + _buffer.length;
          _buffer.clear();
          final left = _quietUntil?.difference(DateTime.now()) ?? Duration.zero;
          _report(
            'dropped $abandoned unsent entries at exit: the server asked for '
            'another ${_seconds(left)}, and a closing sink holds the process '
            'for neither that nor a burst it was told not to send',
          );
          return;
        }
      }
    } finally {
      _pumping = false;
    }
  }

  /// Delivers [batch], retrying what may yet succeed. Answers `false` when
  /// the pump must stop altogether — a wait the server named, abandoned
  /// because the sink is closing.
  Future<bool> _deliver(List<Map<String, dynamic>> batch) async {
    var delay = retryBackoff;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      if (!await _passQuietPeriod()) return false;

      final result = await _send(batch);
      if (result.delivered) {
        _clampAnnounced = false;
        return true;
      }

      if (!result.retryable) {
        _report(
          'server rejected ${batch.length} entries and will not be retried: '
          '${result.error}',
        );
        return true;
      }

      // Set before the attempt count is checked: the moment belongs to the
      // connection, so it holds the batches behind this one even when this
      // one has no attempts left.
      final asked = _quietPeriodFor(result.retryAfter);
      if (asked != null) _quietUntil = DateTime.now().add(asked);

      if (attempt == maxAttempts) {
        _report(
          'giving up on ${batch.length} entries after $maxAttempts attempts: '
          '${result.error}',
        );
        return true;
      }

      // A named moment is waited out by the gate at the top of the next
      // attempt; the backoff is what stands in when nothing was named, and
      // only then does it grow.
      if (asked == null) {
        await Future<void>.delayed(delay);
        delay *= 2;
      }
    }
    return true;
  }
}

/// The real transport: `dart:io`'s [HttpClient], so the package keeps
/// `structured_log` as its only dependency.
class _HttpBatchSender {
  final Uri endpoint;
  final String projectSecretKey;
  final Duration timeout;
  final HttpClient _client = HttpClient();

  _HttpBatchSender({
    required this.endpoint,
    required this.projectSecretKey,
    this.timeout = const Duration(seconds: 30),
  });

  void close() => _client.close(force: true);

  Future<BatchResult> send(List<Map<String, dynamic>> entries) async {
    try {
      final request = await _client.postUrl(endpoint).timeout(timeout);
      request.headers.contentType = ContentType.json;
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $projectSecretKey',
      );
      request.write(jsonEncode(entries));

      final response = await request.close().timeout(timeout);
      // The body has to be drained even when it is not read, or the
      // connection is never returned to the pool.
      await response.drain<void>().timeout(timeout);

      final status = response.statusCode;
      if (status >= 200 && status < 300) return const BatchResult.delivered();
      if (status >= 500) {
        return BatchResult.retryable(
          'HTTP $status',
          retryAfter: _retryAfterOf(response),
        );
      }
      if (status == 408 || status == 429) {
        // Timeouts and throttling are the two 4xx answers that mean "later",
        // not "never".
        return BatchResult.retryable(
          'HTTP $status',
          retryAfter: _retryAfterOf(response),
        );
      }
      return BatchResult.rejected('HTTP $status');
    } on TimeoutException catch (error) {
      return BatchResult.retryable('$error');
    } on SocketException catch (error) {
      return BatchResult.retryable('$error');
    } on HttpException catch (error) {
      return BatchResult.retryable('$error');
    }
  }
}

/// How long `Retry-After` asks for, in both shapes RFC 9110 allows.
///
/// Both are read because the header does not come from the log server —
/// ingestion is not throttled there — but from a proxy or gateway in front
/// of it, and those send delay-seconds and HTTP-dates alike.
///
/// A header that is missing, unparseable, zero, or points at a moment
/// already past answers `null`: there is nothing to wait for, which is not
/// the same as a wait of no length, and the caller's backoff is the better
/// answer in every one of those cases.
Duration? _retryAfterOf(HttpClientResponse response) {
  final header = response.headers.value(HttpHeaders.retryAfterHeader)?.trim();
  if (header == null || header.isEmpty) return null;

  final seconds = int.tryParse(header);
  if (seconds != null) {
    return seconds > 0 ? Duration(seconds: seconds) : null;
  }

  try {
    final delay = HttpDate.parse(header).difference(DateTime.now());
    return delay > Duration.zero ? delay : null;
  } on Exception {
    return null;
  }
}
