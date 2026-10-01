import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:structured_log/structured_log.dart';

/// What a redacted header or query parameter value is replaced with.
///
/// Plain letters rather than something like `<redacted>`: a query value is
/// percent-encoded when the URL is rebuilt, and `%3Credacted%3E` reads worse
/// in a log than the word itself.
const String redactedValue = 'REDACTED';

/// Headers whose values never reach the log, compared case-insensitively.
const Set<String> defaultRedactedHeaders = {
  'authorization',
  'proxy-authorization',
  'cookie',
  'set-cookie',
  'x-api-key',
};

/// Query parameters whose values never reach the log, compared
/// case-insensitively.
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

/// The longest body string [describeHttpBody] keeps before cutting it short.
const int defaultHttpBodyMaxLength = 1000;

/// Turns a request or response body into a value for a log entry; `null`
/// leaves the field out.
typedef HttpBodyDescriber = Object? Function(Object? body);

/// The default [HttpBodyDescriber].
///
/// A string, cut to [defaultHttpBodyMaxLength] characters: maps and lists
/// are JSON-encoded first, raw bytes and streams are summarised rather than
/// dumped, and anything else goes through `toString()`. Never throws — a
/// body that cannot be described becomes a placeholder naming its type.
Object? describeHttpBody(Object? body) {
  if (body == null) return null;
  final String text;
  try {
    text = switch (body) {
      String() => body,
      List<int>() => '<${body.length} bytes>',
      FormData() =>
        '<FormData: ${body.fields.length} fields, ${body.files.length} files>',
      ResponseBody() || Stream() => '<stream>',
      Map() || List() => jsonEncode(body),
      _ => body.toString(),
    };
  } catch (error) {
    return '<${body.runtimeType} could not be described: '
        '${error.runtimeType}>';
  }
  return text.length <= defaultHttpBodyMaxLength
      ? text
      : '${text.substring(0, defaultHttpBodyMaxLength)}…';
}

/// The level each outcome of a call is logged at; `null` turns it off.
///
/// A response's level follows its status code wherever it arrives from —
/// `onResponse` for a status the request's `validateStatus` accepts, or
/// `onError` (as `badResponse`) for one it rejects — so a 404 is a
/// [clientError] either way.
class HttpLogLevels {
  /// The request is about to be sent.
  final LogLevel? request;

  /// A response below 400.
  final LogLevel? success;

  /// A 4xx response.
  final LogLevel? clientError;

  /// A 5xx response.
  final LogLevel? serverError;

  /// No response at all: a timeout, a refused connection, a bad
  /// certificate, or an error thrown by another interceptor or the adapter.
  final LogLevel? failure;

  /// The request was cancelled through its `CancelToken`.
  final LogLevel? cancel;

  const HttpLogLevels({
    this.request = LogLevel.debug,
    this.success = LogLevel.debug,
    this.clientError = LogLevel.warning,
    this.serverError = LogLevel.error,
    this.failure = LogLevel.error,
    this.cancel = LogLevel.debug,
  });
}

/// A dio [Interceptor] that writes every call to `structured_log`.
///
/// ```dart
/// final dio = Dio()..interceptors.add(StructuredLogDioInterceptor());
/// ```
///
/// Add it **last**, so the logged request is the one that actually leaves —
/// with the headers earlier interceptors added — and so it sees a response
/// before any of them can turn it into something else.
///
/// A call produces two entries: `http_request` when it is sent, and then
/// either `http_response` or `http_error`. Both carry `category` (`http` by
/// default), `method`, `url` and `http_request_id`, which pairs them up;
/// the second adds `status_code` (when there was a response) and
/// `duration_ms`, and `http_error` adds `error_type` (the
/// `DioExceptionType`) and, unless the status code already says it all,
/// `error`.
///
/// **What is kept out of the log by default:** headers and bodies are not
/// logged at all until [logHeaders]/[logRequestBody]/[logResponseBody] turn
/// them on, and even then the values of [redactedHeaders] are replaced with
/// [redactedValue]. Query parameters named in [redactedQueryParameters] and
/// any user info in the URL are always redacted.
class StructuredLogDioInterceptor extends Interceptor {
  final BoundLogger? _logger;

  /// The name passed to `getLogger` when no logger was given; it lands in
  /// the `logger` field of every entry.
  final String loggerName;

  /// Bound under `category` on every entry; `null` binds nothing, leaving
  /// whatever category the logger already carries.
  final String? category;

  /// The level of each outcome; see [HttpLogLevels].
  final HttpLogLevels levels;

  /// Whether request and response headers are logged
  /// (`request_headers`/`response_headers`), with [redactedHeaders]
  /// redacted.
  final bool logHeaders;

  /// Whether the request body is logged (`request_body`).
  final bool logRequestBody;

  /// Whether the response body is logged (`response_body`) — on
  /// `http_response`, and on `http_error` when there was a response.
  final bool logResponseBody;

  /// Header names, lower case, whose values are replaced with
  /// [redactedValue].
  final Set<String> redactedHeaders;

  /// Query parameter names, lower case, whose values are replaced with
  /// [redactedValue].
  final Set<String> redactedQueryParameters;

  /// Turns bodies into entry values; see [describeHttpBody].
  final HttpBodyDescriber describeBody;

  /// When given, only requests for which it returns `true` are logged —
  /// both their entries, since the decision is made once, on the request.
  final bool Function(RequestOptions options)? filter;

  int _nextRequestId = 0;

  /// Creates the interceptor.
  ///
  /// Without a [logger] it calls `getLogger(loggerName)` on every entry
  /// rather than once, so a later `StructlogConfiguration.configure` reaches
  /// a `Dio` built before it.
  StructuredLogDioInterceptor({
    BoundLogger? logger,
    this.loggerName = 'dio',
    this.category = 'http',
    this.levels = const HttpLogLevels(),
    this.logHeaders = false,
    this.logRequestBody = false,
    this.logResponseBody = false,
    this.redactedHeaders = defaultRedactedHeaders,
    this.redactedQueryParameters = defaultRedactedQueryParameters,
    this.describeBody = describeHttpBody,
    this.filter,
  }) : _logger = logger;

  static const _callKey = 'structured_log_dio.call';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    _guard(() {
      if (filter != null && !filter!(options)) return;
      final call = _Call(++_nextRequestId);
      options.extra[_callKey] = call;
      _log(levels.request, 'http_request', () {
        return {
          ..._requestFields(options, call),
          if (logHeaders) 'request_headers': _headers(options.headers),
          if (logRequestBody) ..._body('request_body', options.data),
        };
      });
    });
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    _guard(() {
      final call = _callOf(response.requestOptions);
      if (call == null) return;
      _log(_levelForStatus(response.statusCode), 'http_response', () {
        return {
          ..._requestFields(response.requestOptions, call),
          ..._responseFields(response),
          'duration_ms': call.elapsedMs,
        };
      });
    });
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _guard(() {
      final call = _callOf(err.requestOptions);
      if (call == null) return;
      final response = err.response;
      final level = switch (err.type) {
        DioExceptionType.cancel => levels.cancel,
        _ when response != null => _levelForStatus(response.statusCode),
        _ => levels.failure,
      };
      _log(level, 'http_error', () {
        return {
          ..._requestFields(err.requestOptions, call),
          if (response != null) ..._responseFields(response),
          'duration_ms': call.elapsedMs,
          'error_type': err.type.name,
          // A bad response is described by its status code; dio's message
          // for it is a paragraph of boilerplate around that same number.
          if (err.type != DioExceptionType.badResponse)
            if (err.message != null)
              'error': err.message
            else if (err.error != null)
              'error': err.error.toString(),
        };
      });
    });
    handler.next(err);
  }

  /// The interceptor sits in the request path, so nothing it does may stop
  /// a request from going through or change how it ends; a broken
  /// describer or logger costs the entry, never the call.
  void _guard(void Function() body) {
    try {
      body();
    } catch (_) {
      // Deliberately dropped: there is nowhere safe to report it from here.
    }
  }

  /// A request that was filtered out, or sent before this interceptor was
  /// added, has no call record — and so no entries after the first.
  _Call? _callOf(RequestOptions options) {
    final call = options.extra[_callKey];
    return call is _Call ? call : null;
  }

  LogLevel? _levelForStatus(int? statusCode) {
    if (statusCode == null || statusCode < 400) return levels.success;
    if (statusCode < 500) return levels.clientError;
    return levels.serverError;
  }

  void _log(
    LogLevel? level,
    String event,
    Map<String, dynamic> Function() fields,
  ) {
    if (level == null) return;
    Map<String, dynamic> described;
    try {
      described = fields();
    } catch (error) {
      described = {'describe_failed': error.runtimeType.toString()};
    }
    (_logger ?? getLogger(loggerName)).tryLog(
      level,
      event,
      context: {
        if (category != null) 'category': category,
        ...described,
      },
    );
  }

  Map<String, dynamic> _requestFields(RequestOptions options, _Call call) => {
        'http_request_id': call.id,
        'method': options.method,
        'url': _redactUrl(options.uri),
      };

  Map<String, dynamic> _responseFields(Response<dynamic> response) => {
        if (response.statusCode != null) 'status_code': response.statusCode,
        if (logHeaders) 'response_headers': _headers(response.headers.map),
        if (logResponseBody) ..._body('response_body', response.data),
      };

  Map<String, dynamic> _body(String key, Object? body) {
    final described = describeBody(body);
    return described == null ? const {} : {key: described};
  }

  /// Header values as strings — a multi-valued header joined the way it
  /// would be on the wire — with [redactedHeaders] replaced.
  Map<String, String> _headers(Map<String, dynamic> headers) => {
        for (final MapEntry(:key, :value) in headers.entries)
          key: redactedHeaders.contains(key.toLowerCase())
              ? redactedValue
              : (value is List ? value.join(', ') : '$value'),
      };

  String _redactUrl(Uri uri) {
    var redacted = uri.userInfo.isEmpty ? uri : uri.replace(userInfo: '');
    final query = redacted.queryParametersAll;
    if (query.keys.any(
      (name) => redactedQueryParameters.contains(name.toLowerCase()),
    )) {
      redacted = redacted.replace(queryParameters: {
        for (final MapEntry(:key, :value) in query.entries)
          key: redactedQueryParameters.contains(key.toLowerCase())
              ? [for (final _ in value) redactedValue]
              : value,
      });
    }
    return redacted.toString();
  }
}

/// What the interceptor remembers about a call between its request and
/// its outcome, carried in the request's `extra`.
class _Call {
  final int id;
  final Stopwatch _stopwatch = Stopwatch()..start();

  _Call(this.id);

  int get elapsedMs => _stopwatch.elapsedMilliseconds;
}
