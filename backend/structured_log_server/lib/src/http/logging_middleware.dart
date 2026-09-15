import 'dart:math';

import 'package:shelf/shelf.dart';
import 'package:structured_log/structured_log.dart';

/// Records one `request.completed` entry per request (`design.md`
/// decision 48).
///
/// Structured fields rather than an interpolated sentence: `method`, `path`,
/// `status` and `duration_ms` are what someone greps, sorts and counts, and
/// making the server's own log machine-readable is the same thing the
/// library offers its users.
///
/// What is deliberately absent is as important as what is present. The
/// request body never appears — it carries passwords on the token endpoint
/// and tenant data on the ingest endpoint — and neither does the
/// `Authorization` header, which carries an access token or a project
/// secret key verbatim. Logging a whole request object is the ordinary way
/// this goes wrong, so nothing here ever touches one.
///
/// Level follows the outcome: `info` for 2xx/3xx, `warning` for 4xx (a
/// caller's problem), `error` for 5xx (ours).
///
/// Placed outermost in the pipeline, so the status it records is the one the
/// client actually received — including responses rendered by the error
/// middleware below it.
Middleware requestLoggingMiddleware(
  BoundLogger logger, {
  String Function()? requestId,
  DateTime Function()? clock,
}) {
  final newId = requestId ?? _randomRequestId;
  final now = clock ?? DateTime.now;

  return (Handler innerHandler) {
    return (Request request) async {
      final started = now();
      // Correlation comes from `LogCorrelation`'s existing vocabulary rather
      // than a field invented here, so a request can be followed across the
      // server's own log the same way it is followed in a tenant's.
      final scoped = logger.withCorrelation(requestId: newId());

      Response response;
      try {
        response = await innerHandler(request);
      } catch (error, stackTrace) {
        // An error that reached this far never produced a response; it still
        // has to be recorded, and with its stack, because nothing below will
        // report it.
        scoped.error(
          'request.failed',
          context: {
            'method': request.method,
            'path': '/${request.url.path}',
            'duration_ms': now().difference(started).inMilliseconds,
            'error': '$error',
            'stack_trace': '$stackTrace',
          },
        );
        rethrow;
      }

      final status = response.statusCode;
      scoped.tryLog(
        _levelFor(status),
        'request.completed',
        context: {
          'method': request.method,
          'path': '/${request.url.path}',
          'status': status,
          'duration_ms': now().difference(started).inMilliseconds,
        },
      );

      return response;
    };
  };
}

LogLevel _levelFor(int status) {
  if (status >= 500) return LogLevel.error;
  if (status >= 400) return LogLevel.warning;
  return LogLevel.info;
}

final _random = Random();

/// Short and random — enough to tie a request's entries together within a
/// log, and not a secret, so `Random` is the right tool rather than
/// `Random.secure`.
String _randomRequestId() {
  const alphabet = '0123456789abcdef';
  return List.generate(12, (_) => alphabet[_random.nextInt(16)]).join();
}
