import 'dart:convert';

import 'package:shelf/shelf.dart';

/// A domain failure that a route handler throws to have it rendered as the
/// general JSON error envelope `log-server-api` requires:
/// `{"error": "<code>", "message": "...", "details": {...}}` (`details` is
/// omitted when absent). This is the envelope every endpoint uses *except*
/// `POST`/`DELETE /v1/auth/token`, which answers in the RFC 6749 §5.2 shape
/// instead (`TokenService`'s own error type, `TokenError`, not this one).
class ApiError implements Exception {
  final int statusCode;
  final String code;
  final String message;
  final Map<String, Object?>? details;

  /// Extra response headers this failure carries — `Retry-After` on a
  /// `429`, and nothing else so far.
  final Map<String, String>? headers;

  const ApiError(
    this.statusCode,
    this.code,
    this.message, {
    this.details,
    this.headers,
  });

  factory ApiError.invalidRequest(
    String message, {
    Map<String, Object?>? details,
  }) =>
      ApiError(400, 'invalid_request', message, details: details);

  factory ApiError.unauthorized([String message = 'Unauthorized.']) =>
      ApiError(401, 'unauthorized', message);

  factory ApiError.forbidden([String message = 'Access denied.']) =>
      ApiError(403, 'forbidden', message);

  /// The account authenticated fine but holds a temporary password, so every
  /// endpoint except the small allowlist is closed to it until it changes
  /// (`log-server-forced-password-change`). Distinct code from
  /// [ApiError.forbidden] — the client reacts by prompting for a new
  /// password, not by reporting a missing right.
  factory ApiError.mustChangePassword() => ApiError(
        403,
        'must_change_password',
        'This account must change its password before continuing.',
      );

  factory ApiError.notFound([String message = 'Resource not found.']) =>
      ApiError(404, 'not_found', message);

  /// Throttled by `log-server-rate-limit`. [retryAfter] is rounded up to
  /// whole seconds, and at least one — `Retry-After: 0` would invite an
  /// immediate retry that is certain to be rejected again.
  ///
  /// This is the one place `POST /v1/auth/token` answers in the general
  /// envelope instead of the RFC 6749 shape (`design.md` decision 43): the
  /// rejection happens before the request is understood as a grant at all.
  factory ApiError.tooManyRequests(Duration retryAfter) {
    final seconds = (retryAfter.inMilliseconds / 1000).ceil();
    return ApiError(
      429,
      'too_many_requests',
      'Too many requests. Retry later.',
      headers: {'retry-after': '${seconds < 1 ? 1 : seconds}'},
    );
  }

  Response toResponse() {
    final body = <String, Object?>{'error': code, 'message': message};
    if (details != null) body['details'] = details;
    return Response(
      statusCode,
      body: jsonEncode(body),
      headers: {
        'content-type': 'application/json',
        ...?headers,
      },
    );
  }

  @override
  String toString() => 'ApiError($statusCode, $code, $message)';
}

/// Catches [ApiError] thrown by a route handler and renders it as the JSON
/// error envelope above, so individual handlers can `throw` instead of
/// threading error responses through every return path.
Middleware errorHandlingMiddleware() {
  return (Handler innerHandler) {
    return (Request request) async {
      try {
        return await innerHandler(request);
      } on ApiError catch (e) {
        return e.toResponse();
      }
    };
  };
}
