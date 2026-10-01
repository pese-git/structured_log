import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
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
///
/// It receives what [StructuredLogHttpClient] could read without changing
/// the call: the text of a textual body (already cut short, ending in `…`,
/// if the body was longer than what was kept), or a placeholder such as
/// `<42 bytes>` for a binary one, `<stream>` for a streamed request, or
/// `<multipart: 2 fields, 1 files>`.
typedef HttpBodyDescriber = Object? Function(String body);

/// The default [HttpBodyDescriber]: the body cut to
/// [defaultHttpBodyMaxLength] characters.
Object? describeHttpBody(String body) => body.length <= defaultHttpBodyMaxLength
    ? body
    : '${body.substring(0, defaultHttpBodyMaxLength)}…';

/// The level each outcome of a call is logged at; `null` turns it off.
///
/// `package:http` does not throw on a status code, so every response is an
/// `http_response`, and its level follows the status.
class HttpLogLevels {
  /// The request is about to be sent.
  final LogLevel? request;

  /// A response below 400.
  final LogLevel? success;

  /// A 4xx response.
  final LogLevel? clientError;

  /// A 5xx response.
  final LogLevel? serverError;

  /// No response at all: the inner client threw — a refused connection, a
  /// timeout, a TLS failure — or the response body failed half-way.
  final LogLevel? failure;

  /// The request was aborted through its `abortTrigger`.
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

/// An `http.Client` that writes every call it makes to `structured_log`,
/// sending it through [inner].
///
/// ```dart
/// final client = StructuredLogHttpClient(http.Client());
/// await client.get(Uri.parse('https://api.example.com/items'));
/// ```
///
/// A call produces two entries: `http_request` when it is sent, and then
/// `http_response` — whatever the status — or `http_error` if no response
/// arrived. Both carry `category` (`http` by default), `method`, `url` and
/// `http_request_id`, which pairs them up; the outcome adds `status_code`
/// and `duration_ms`, and `http_error` adds `error_type` (the exception's
/// type) and `error`.
///
/// **When the response is logged.** Without [logResponseBody],
/// `http_response` is written as soon as the headers arrive, and
/// `duration_ms` is the time to them. With it, the body has to pass
/// through first, so the entry is written once the body has been read to
/// its end (or the reader stopped reading), and `duration_ms` covers the
/// body too. The body is not buffered: it reaches the reader as it
/// arrives, and only the first part of it is kept for the log — but a
/// response that is never read to the end, such as a server-sent event
/// stream left open, is logged only when its reader cancels.
///
/// **What is kept out of the log by default:** headers and bodies are not
/// logged until [logHeaders]/[logRequestBody]/[logResponseBody] turn them
/// on, and even then the values of [redactedHeaders] are replaced with
/// [redactedValue]. Query parameters named in [redactedQueryParameters] and
/// any user info in the URL are always redacted.
class StructuredLogHttpClient extends http.BaseClient {
  /// The client that actually sends the requests.
  final http.Client inner;

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

  /// Whether the response body is logged (`response_body`); see the class
  /// documentation for how this moves the `http_response` entry.
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
  final bool Function(http.BaseRequest request)? filter;

  int _nextRequestId = 0;

  /// Wraps [inner].
  ///
  /// Without a [logger] it calls `getLogger(loggerName)` on every entry
  /// rather than once, so a later `StructlogConfiguration.configure`
  /// reaches a client built before it.
  StructuredLogHttpClient(
    this.inner, {
    BoundLogger? logger,
    this.loggerName = 'http',
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

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final call = _guard(() => _startCall(request));
    if (call == null) return inner.send(request);

    final http.StreamedResponse response;
    try {
      response = await inner.send(request);
    } catch (error) {
      _guard(() => _logFailure(call, error));
      rethrow;
    }

    if (!logResponseBody) {
      _guard(() => _logResponse(call, response));
      return response;
    }
    return _withLoggedBody(call, response);
  }

  @override
  void close() => inner.close();

  /// Logs the request and returns its call record, or `null` if it is not
  /// to be logged.
  _Call? _startCall(http.BaseRequest request) {
    if (filter != null && !filter!(request)) return null;
    final call = _Call(
      id: ++_nextRequestId,
      method: request.method,
      url: _redactUrl(request.url),
    );
    _log(levels.request, 'http_request', () {
      return {
        ...call.fields,
        if (logHeaders) 'request_headers': _headers(request.headers),
        if (logRequestBody) ..._body('request_body', _requestBody(request)),
      };
    });
    return call;
  }

  /// [body] is described inside the entry's builder, so a describer that
  /// throws costs the entry its fields, not the entry itself.
  void _logResponse(
    _Call call,
    http.StreamedResponse response, {
    String? body,
  }) {
    _log(_levelForStatus(response.statusCode), 'http_response', () {
      return {
        ...call.fields,
        'status_code': response.statusCode,
        'duration_ms': call.elapsedMs,
        if (logHeaders) 'response_headers': _headers(response.headers),
        if (body != null) ..._body('response_body', body),
      };
    });
  }

  void _logFailure(_Call call, Object error, {int? statusCode}) {
    final level =
        error is http.RequestAbortedException ? levels.cancel : levels.failure;
    _log(level, 'http_error', () {
      return {
        ...call.fields,
        if (statusCode != null) 'status_code': statusCode,
        'duration_ms': call.elapsedMs,
        'error_type': error.runtimeType.toString(),
        'error': error is http.ClientException ? error.message : '$error',
      };
    });
  }

  /// Hands the reader the body as it arrives and keeps a copy of its start
  /// for the log, written when the body ends, fails, or the reader stops.
  http.StreamedResponse _withLoggedBody(
    _Call call,
    http.StreamedResponse response,
  ) {
    final textual = _isTextual(response.headers['content-type']);
    final capture = _Capture(_captureLimit);
    var logged = false;
    void finish(Object? error) {
      if (logged) return;
      logged = true;
      _guard(() {
        if (error != null) {
          _logFailure(call, error, statusCode: response.statusCode);
        } else {
          _logResponse(
            call,
            response,
            body: textual ? capture.text : '<${capture.total} bytes>',
          );
        }
      });
    }

    late final StreamSubscription<List<int>> source;
    final controller = StreamController<List<int>>(sync: true);
    controller
      ..onListen = () {
        source = response.stream.listen(
          (chunk) {
            capture.add(chunk);
            controller.add(chunk);
          },
          onError: (Object error, StackTrace stackTrace) {
            finish(error);
            controller.addError(error, stackTrace);
          },
          onDone: () {
            finish(null);
            controller.close();
          },
        );
      }
      ..onPause = (() => source.pause())
      ..onResume = (() => source.resume())
      ..onCancel = () {
        finish(null);
        return source.cancel();
      };

    final request = response.request;
    final headers = response.headers;
    if (response case http.BaseResponseWithUrl(:final url)) {
      return _StreamedResponseWithUrl(
        controller.stream,
        response.statusCode,
        url: url,
        contentLength: response.contentLength,
        request: request,
        headers: headers,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase,
      );
    }
    return http.StreamedResponse(
      controller.stream,
      response.statusCode,
      contentLength: response.contentLength,
      request: request,
      headers: headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  /// UTF-8 needs at most four bytes a character, so this many bytes always
  /// hold enough text for the default describer to cut.
  static const _captureLimit = defaultHttpBodyMaxLength * 4;

  String _requestBody(http.BaseRequest request) => switch (request) {
        http.MultipartRequest(:final fields, :final files) =>
          '<multipart: ${fields.length} fields, ${files.length} files>',
        http.Request(:final bodyBytes, :final headers) =>
          _isTextual(headers['content-type'])
              ? _textOf(bodyBytes.take(_captureLimit).toList(),
                  truncated: bodyBytes.length > _captureLimit)
              : '<${bodyBytes.length} bytes>',
        _ => '<stream>',
      };

  /// The client sits in the request path, so nothing it does may stop
  /// a request from going through or change how it ends; a broken
  /// describer or logger costs the entry, never the call.
  T? _guard<T>(T Function() body) {
    try {
      return body();
    } catch (_) {
      // Deliberately dropped: there is nowhere safe to report it from here.
      return null;
    }
  }

  LogLevel? _levelForStatus(int statusCode) {
    if (statusCode < 400) return levels.success;
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

  Map<String, dynamic> _body(String key, String body) {
    final described = describeBody(body);
    return described == null ? const {} : {key: described};
  }

  Map<String, String> _headers(Map<String, String> headers) => {
        for (final MapEntry(:key, :value) in headers.entries)
          key: redactedHeaders.contains(key.toLowerCase())
              ? redactedValue
              : value,
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

  /// Whether a body of this content type is worth logging as text; without
  /// a content type it is assumed to be, since most APIs that omit it
  /// answer in text.
  static bool _isTextual(String? contentType) {
    if (contentType == null) return true;
    final type = contentType.split(';').first.trim().toLowerCase();
    return type.startsWith('text/') ||
        type.endsWith('json') ||
        type.endsWith('xml') ||
        type == 'application/x-www-form-urlencoded' ||
        type == 'application/javascript';
  }

  static String _textOf(List<int> bytes, {required bool truncated}) {
    final text = utf8.decode(bytes, allowMalformed: true);
    return truncated ? '$text…' : text;
  }
}

/// A response that keeps the final URL of the one it replaces.
///
/// `package:http`'s own class for this is not exported, so a wrapped
/// response would otherwise lose `BaseResponseWithUrl.url` — the URL after
/// redirects — to the reader.
class _StreamedResponseWithUrl extends http.StreamedResponse
    implements http.BaseResponseWithUrl {
  @override
  final Uri url;

  _StreamedResponseWithUrl(
    super.stream,
    super.statusCode, {
    required this.url,
    super.contentLength,
    super.request,
    super.headers,
    super.isRedirect,
    super.persistentConnection,
    super.reasonPhrase,
  });
}

/// What the client remembers about a call between its request and its
/// outcome.
class _Call {
  final int id;
  final String method;
  final String url;
  final Stopwatch _stopwatch = Stopwatch()..start();

  _Call({required this.id, required this.method, required this.url});

  Map<String, dynamic> get fields =>
      {'http_request_id': id, 'method': method, 'url': url};

  int get elapsedMs => _stopwatch.elapsedMilliseconds;
}

/// The first [limit] bytes of a body, and how many there were in all.
class _Capture {
  final int limit;
  final List<int> _bytes = [];
  int total = 0;

  _Capture(this.limit);

  void add(List<int> chunk) {
    total += chunk.length;
    final room = limit - _bytes.length;
    if (room > 0) _bytes.addAll(chunk.take(room));
  }

  String get text => StructuredLogHttpClient._textOf(
        _bytes,
        truncated: total > _bytes.length,
      );
}
