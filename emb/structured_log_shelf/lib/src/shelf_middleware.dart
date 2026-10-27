import 'dart:math';

import 'package:shelf/shelf.dart';
import 'package:structured_log/structured_log.dart';

/// What a redacted header or query parameter value is replaced with.
const String redactedValue = 'REDACTED';

/// Headers whose values never reach the log, compared case-insensitively —
/// the same set as `structured_log_dio`'s.
const Set<String> defaultRedactedHeaders = {
  'authorization',
  'proxy-authorization',
  'cookie',
  'set-cookie',
  'x-api-key',
};

/// Query parameters whose values never reach the log, compared
/// case-insensitively — the same set as `structured_log_dio`'s.
const Set<String> defaultRedactedQueryParameters = {
  'access_token',
  'refresh_token',
  'id_token',
  'token',
  'api_key',
  'apikey',
  'password',
  'client_secret',
};

/// The header a request id is returned in, and read from when incoming ids
/// are trusted.
const String defaultRequestIdHeader = 'X-Request-Id';

const String _loggerKey = 'structured_log_shelf.logger';
const String _requestIdKey = 'structured_log_shelf.request_id';

/// What an incoming id has to look like to be used: long enough to be an
/// id, short enough not to be a payload, and made of characters a UUID or
/// a proxy's id uses — nothing that could break a log line or a viewer.
final RegExp _acceptableRequestId = RegExp(r'^[A-Za-z0-9._:-]{1,128}$');

/// The level of each outcome of a request; `null` turns that entry off.
class ShelfLogLevels {
  /// The request arrived, before the handler runs. Off by default: worth it
  /// for long requests such as server-sent events, double the log for the
  /// rest.
  final LogLevel? received;

  /// A response below 400.
  final LogLevel? success;

  /// A 4xx response.
  final LogLevel? clientError;

  /// A 5xx response.
  final LogLevel? serverError;

  /// The handler threw instead of responding.
  final LogLevel? failure;

  const ShelfLogLevels({
    this.received,
    this.success = LogLevel.info,
    this.clientError = LogLevel.warning,
    this.serverError = LogLevel.error,
    this.failure = LogLevel.error,
  });
}

/// The logger and id [structuredLogRequests] bound to a request.
extension StructuredLogRequest on Request {
  /// A logger bound to this request's `request_id`: every entry written
  /// through it can be told apart from those of concurrent requests.
  ///
  /// Throws a [StateError] when the request did not pass through
  /// [structuredLogRequests] — rather than quietly returning a logger
  /// without the id, which would hide exactly the wiring mistake that
  /// leaves entries uncorrelated.
  BoundLogger get logger => _read<BoundLogger>(_loggerKey, 'logger');

  /// This request's id, as written in `request_id` and returned to the
  /// client.
  ///
  /// Throws a [StateError] when the request did not pass through
  /// [structuredLogRequests].
  String get requestId => _read<String>(_requestIdKey, 'requestId');

  T _read<T>(String key, String name) {
    final value = context[key];
    if (value is T) return value;
    throw StateError(
      'request.$name is set by structuredLogRequests(); add it to the '
      'Pipeline in front of this handler',
    );
  }
}

/// A shelf [Middleware] that writes every request to `structured_log` and
/// gives the handler a logger bound to the request's id.
///
/// ```dart
/// final handler = const Pipeline()
///     .addMiddleware(structuredLogRequests())
///     .addHandler((request) {
///   request.logger.info('items_listed');
///   return Response.ok('[]');
/// });
/// ```
///
/// Put it first in the `Pipeline`: the status it records is then the one the
/// client received, including responses made by error-handling middleware
/// inside it.
///
/// Each request ends in one entry: `http_request_handled` when the handler
/// responded — with `method`, `path`, `status_code` and `duration_ms` — or
/// `http_request_failed` when it threw, with the error and its stack, after
/// which the error is rethrown unchanged. A request whose socket the handler
/// took over is `http_request_handled` with `hijacked: true` and no status.
/// `duration_ms` is the time until the handler returned its response, not
/// until the body was sent. With [ShelfLogLevels.received] set, an
/// `http_request_received` entry is written before the handler runs.
///
/// Every request gets an id, made by [requestIdGenerator] (12 random hex
/// characters by default). It is bound as `request_id` to every entry this
/// middleware writes and to [StructuredLogRequest.logger], and returned in
/// the [responseHeader] of the response; `null` leaves the header off. An
/// incoming id in [incomingRequestIdHeader] is used only when
/// [trustIncomingRequestId] is on — behind a proxy that sets it — and only if
/// it is 1–128 characters of `[A-Za-z0-9._:-]`; any other value is replaced,
/// the entry gets `request_id_rejected: true`, and the value itself is
/// written nowhere.
///
/// Bodies are never written; there is no setting for it. Headers are written
/// only with [logHeaders], as `request_headers` and `response_headers`, with
/// the values of [redactedHeaders] replaced with [redactedValue]. A
/// non-empty query is written as `query`, with the values of
/// [redactedQueryParameters] replaced. A secret in a path segment
/// (`/reset/<token>`) cannot be told from the path alone — keep such routes
/// out with [filter].
///
/// [filter] decides whether this middleware writes entries for a request;
/// a request it rejects still gets its id, its logger and the response
/// header. A filter that throws costs the request its entries, never its
/// response, and so does anything else that goes wrong while logging.
///
/// Without a [logger] it calls `getLogger(loggerName)` on every request, so
/// a configuration made after the `Pipeline` was built applies.
Middleware structuredLogRequests({
  BoundLogger? logger,
  String loggerName = 'shelf',
  String? category = 'http',
  ShelfLogLevels levels = const ShelfLogLevels(),
  bool Function(Request request)? filter,
  bool logHeaders = false,
  Set<String> redactedHeaders = defaultRedactedHeaders,
  Set<String> redactedQueryParameters = defaultRedactedQueryParameters,
  String Function()? requestIdGenerator,
  String? responseHeader = defaultRequestIdHeader,
  bool trustIncomingRequestId = false,
  String incomingRequestIdHeader = defaultRequestIdHeader,
}) {
  final requests = _RequestLogger(
    logger: logger,
    loggerName: loggerName,
    category: category,
    levels: levels,
    filter: filter,
    logHeaders: logHeaders,
    redactedHeaders: {for (final name in redactedHeaders) name.toLowerCase()},
    redactedQueryParameters: {
      for (final name in redactedQueryParameters) name.toLowerCase(),
    },
    requestIdGenerator: requestIdGenerator ?? _randomRequestId,
    responseHeader: responseHeader,
    trustIncomingRequestId: trustIncomingRequestId,
    incomingRequestIdHeader: incomingRequestIdHeader,
  );
  return (Handler innerHandler) =>
      (Request request) => requests.handle(request, innerHandler);
}

class _RequestLogger {
  final BoundLogger? _logger;
  final String loggerName;
  final String? category;
  final ShelfLogLevels levels;
  final bool Function(Request request)? filter;
  final bool logHeaders;
  final Set<String> redactedHeaders;
  final Set<String> redactedQueryParameters;
  final String Function() requestIdGenerator;
  final String? responseHeader;
  final bool trustIncomingRequestId;
  final String incomingRequestIdHeader;

  _RequestLogger({
    required BoundLogger? logger,
    required this.loggerName,
    required this.category,
    required this.levels,
    required this.filter,
    required this.logHeaders,
    required this.redactedHeaders,
    required this.redactedQueryParameters,
    required this.requestIdGenerator,
    required this.responseHeader,
    required this.trustIncomingRequestId,
    required this.incomingRequestIdHeader,
  }) : _logger = logger;

  Future<Response> handle(Request request, Handler innerHandler) async {
    final stopwatch = Stopwatch()..start();
    final (id, rejected) = _requestIdOf(request);
    final log = (_logger ?? getLogger(loggerName)).withCorrelation(
      requestId: id,
    );
    final logged = _accepts(request);

    if (logged) {
      _emit(
          log,
          levels.received,
          'http_request_received',
          () => {
                ..._requestFields(request, rejected),
              });
    }

    final Response response;
    try {
      response = await innerHandler(
        request.change(context: {_loggerKey: log, _requestIdKey: id}),
      );
    } on HijackException {
      // Not a failure: the handler took the socket and answered on it
      // itself, so there is no response to record or to add a header to.
      if (logged) {
        _emit(
            log,
            levels.success,
            'http_request_handled',
            () => {
                  ..._requestFields(request, rejected),
                  'hijacked': true,
                  'duration_ms': _millis(stopwatch),
                });
      }
      rethrow;
    } catch (error, stackTrace) {
      if (logged) {
        _emit(
          log,
          levels.failure,
          'http_request_failed',
          () => {
            ..._requestFields(request, rejected),
            'duration_ms': _millis(stopwatch),
          },
          error: error,
          stackTrace: stackTrace,
        );
      }
      rethrow;
    }

    if (logged) {
      _emit(
          log,
          _levelFor(response.statusCode),
          'http_request_handled',
          () => {
                ..._requestFields(request, rejected),
                'status_code': response.statusCode,
                'duration_ms': _millis(stopwatch),
                if (logHeaders) 'response_headers': _headers(response.headers),
              });
    }
    return _withRequestId(response, id);
  }

  /// The id to use and whether an incoming one was turned down. A broken
  /// generator falls back to the default one: the request needs an id more
  /// than it needs that particular kind of id.
  (String, bool) _requestIdOf(Request request) {
    var rejected = false;
    if (trustIncomingRequestId) {
      final incoming = request.headers[incomingRequestIdHeader];
      if (incoming != null) {
        if (_acceptableRequestId.hasMatch(incoming)) return (incoming, false);
        rejected = true;
      }
    }
    String id;
    try {
      id = requestIdGenerator();
    } catch (_) {
      id = _randomRequestId();
    }
    return (id, rejected);
  }

  /// Fail-closed: a filter that throws costs the request its entries — a
  /// filter is how noisy or sensitive routes are kept out, and writing them
  /// anyway would be the wrong way to fail.
  bool _accepts(Request request) {
    final filter = this.filter;
    if (filter == null) return true;
    try {
      return filter(request);
    } catch (_) {
      return false;
    }
  }

  LogLevel? _levelFor(int statusCode) {
    if (statusCode < 400) return levels.success;
    if (statusCode < 500) return levels.clientError;
    return levels.serverError;
  }

  /// Nothing here may change how a request ends: an entry that cannot be
  /// built or written is dropped, and the request goes on.
  void _emit(
    BoundLogger log,
    LogLevel? level,
    String event,
    Map<String, dynamic> Function() fields, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (level == null) return;
    try {
      if (!log.isEnabled(level)) return;
      log.tryLog(
        level,
        event,
        context: {
          if (category != null) 'category': category,
          ...fields(),
        },
        error: error,
        stackTrace: stackTrace,
      );
    } catch (_) {
      // Deliberately dropped: there is nowhere safe to report it from here.
    }
  }

  /// What every entry of a request carries, whatever its outcome.
  Map<String, dynamic> _requestFields(Request request, bool rejected) {
    final uri = request.requestedUri;
    return {
      'method': request.method,
      'path': uri.path,
      if (uri.query.isNotEmpty) 'query': _redactQuery(uri),
      if (rejected) 'request_id_rejected': true,
      if (logHeaders) 'request_headers': _headers(request.headers),
    };
  }

  String _redactQuery(Uri uri) {
    final query = uri.queryParametersAll;
    if (!query.keys.any(
      (name) => redactedQueryParameters.contains(name.toLowerCase()),
    )) {
      return uri.query;
    }
    return uri.replace(queryParameters: {
      for (final MapEntry(:key, :value) in query.entries)
        key: redactedQueryParameters.contains(key.toLowerCase())
            ? [for (final _ in value) redactedValue]
            : value,
    }).query;
  }

  Map<String, String> _headers(Map<String, String> headers) => {
        for (final MapEntry(:key, :value) in headers.entries)
          key.toLowerCase(): redactedHeaders.contains(key.toLowerCase())
              ? redactedValue
              : value,
      };

  /// A response the header could not be added to goes out as it is.
  Response _withRequestId(Response response, String id) {
    final header = responseHeader;
    if (header == null) return response;
    try {
      return response.change(headers: {header: id});
    } catch (_) {
      return response;
    }
  }
}

double _millis(Stopwatch stopwatch) =>
    stopwatch.elapsedMicroseconds / Duration.microsecondsPerMillisecond;

final _random = Random();

/// Short and random — enough to tie a request's entries together, and not a
/// secret, so `Random` rather than `Random.secure`.
String _randomRequestId() {
  const alphabet = '0123456789abcdef';
  return List.generate(12, (_) => alphabet[_random.nextInt(16)]).join();
}
