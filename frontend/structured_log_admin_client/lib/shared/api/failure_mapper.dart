import 'package:dio/dio.dart';

import 'api_failure.dart';

/// Turns whatever `dio` threw into the failure the rest of the app reasons
/// about.
///
/// One place, so a screen never inspects a status code: the server states its
/// errors as `{"error": code, "message": ..., "details": {...}}`, and that
/// shape is decoded here once.
ApiFailure mapDioException(DioException error) {
  switch (error.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.transformTimeout:
      return const ApiFailure.network(message: 'The server did not answer.');
    case DioExceptionType.connectionError:
    case DioExceptionType.unknown:
      return ApiFailure.network(message: error.message);
    case DioExceptionType.cancel:
      return const ApiFailure.network(message: 'The request was cancelled.');
    case DioExceptionType.badCertificate:
      return const ApiFailure.network(
        message: 'The server certificate was rejected.',
      );
    case DioExceptionType.badResponse:
      break;
  }

  final response = error.response;
  if (response == null) return ApiFailure.network(message: error.message);
  return mapErrorResponse(response);
}

/// The `{"error", "message", "details"}` envelope, by status.
ApiFailure mapErrorResponse(Response<dynamic> response) {
  final body = response.data;
  final envelope = body is Map<String, dynamic> ? body : const {};
  // `error` is the server's own code; the fallbacks only matter for a
  // response that never came from this server — a proxy's error page, say.
  final code = envelope['error'] as String? ?? 'unknown';
  final message = envelope['message'] as String?;
  final details = envelope['details'] as Map<String, dynamic>?;

  switch (response.statusCode) {
    case 400:
      return ApiFailure.invalidRequest(
        code: code,
        message: message,
        details: details,
      );
    case 401:
      return ApiFailure.unauthorized(code: code, message: message);
    case 403:
      return ApiFailure.forbidden(
        code: code,
        message: message,
        details: details,
      );
    case 404:
      return ApiFailure.notFound(code: code, message: message);
    case 409:
      return ApiFailure.conflict(
        code: code,
        message: message,
        details: details,
      );
    case 429:
      return ApiFailure.rateLimited(
        retryAfter: retryAfterOf(response),
        message: message,
      );
    default:
      return ApiFailure.server(
        statusCode: response.statusCode ?? 0,
        code: code,
        message: message,
      );
  }
}

/// How long `Retry-After` says to wait.
///
/// Only the delay-seconds form is read: that is what the server sends
/// (`log-server-rate-limit`). An HTTP-date, or a header that is missing or
/// unparseable, falls back to a minute — long enough not to hammer a limiter
/// that is already refusing, and the countdown a screen shows is honest about
/// being a guess only in that it never came from the server.
Duration retryAfterOf(Response<dynamic> response) {
  final header = response.headers.value('retry-after');
  final seconds = header == null ? null : int.tryParse(header.trim());
  return Duration(seconds: seconds ?? 60);
}
