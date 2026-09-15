import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log_admin_client/shared/api/api_failure.dart';
import 'package:structured_log_admin_client/shared/api/failure_mapper.dart';

Response<dynamic> _response(
  int status, {
  Object? body,
  Map<String, List<String>>? headers,
}) {
  return Response<dynamic>(
    requestOptions: RequestOptions(path: '/v1/groups'),
    statusCode: status,
    data: body,
    headers: Headers.fromMap(headers ?? const {}),
  );
}

void main() {
  test('the server envelope becomes a typed failure', () {
    final failure = mapErrorResponse(
      _response(
        403,
        body: {
          'error': 'must_change_password',
          'message': 'Change your password first.',
        },
      ),
    );

    expect(
      failure,
      const ApiFailure.forbidden(
        code: 'must_change_password',
        message: 'Change your password first.',
      ),
    );
  });

  test('each status maps to its own case', () {
    final cases = <int, Type>{
      400: InvalidRequestFailure,
      401: UnauthorizedFailure,
      403: ForbiddenFailure,
      404: NotFoundFailure,
      409: ConflictFailure,
      429: RateLimitedFailure,
      500: ServerFailure,
      503: ServerFailure,
    };

    cases.forEach((status, type) {
      final failure = mapErrorResponse(_response(status, body: {'error': 'x'}));
      expect(failure.runtimeType, type, reason: 'status $status');
    });
  });

  test('429 carries the wait from Retry-After', () {
    final failure = mapErrorResponse(
      _response(
        429,
        body: {'error': 'rate_limited'},
        headers: {
          'retry-after': ['42'],
        },
      ),
    );

    expect(failure, isA<RateLimitedFailure>());
    expect(
      (failure as RateLimitedFailure).retryAfter,
      const Duration(seconds: 42),
    );
  });

  test('a missing or unparseable Retry-After falls back to a minute', () {
    for (final headers in [
      <String, List<String>>{},
      {
        'retry-after': ['Wed, 21 Oct 2026 07:28:00 GMT'],
      },
    ]) {
      final failure = mapErrorResponse(
        _response(429, body: {'error': 'rate_limited'}, headers: headers),
      );
      expect(
        (failure as RateLimitedFailure).retryAfter,
        const Duration(seconds: 60),
      );
    }
  });

  test('a body that is not the envelope still yields a failure', () {
    // A proxy's HTML error page, say — the code is unknown but the status
    // still means something.
    final failure = mapErrorResponse(_response(502, body: '<html>'));
    expect(failure, isA<ServerFailure>());
    expect((failure as ServerFailure).statusCode, 502);
  });

  test('transport problems map to network, not to a status', () {
    for (final type in [
      DioExceptionType.connectionTimeout,
      DioExceptionType.receiveTimeout,
      DioExceptionType.connectionError,
      DioExceptionType.cancel,
      DioExceptionType.badCertificate,
    ]) {
      final failure = mapDioException(
        DioException(
          requestOptions: RequestOptions(path: '/v1/groups'),
          type: type,
        ),
      );
      expect(failure, isA<NetworkFailure>(), reason: '$type');
    }
  });
}
