import 'package:shelf/shelf.dart';

/// Methods and headers every route this server has actually needs — fixed
/// constants rather than an echo of the request's own
/// `Access-Control-Request-Method`/`-Headers`, because there is nothing to
/// gain by reflecting a request's ask back at it when the true answer never
/// changes.
const _allowedMethods = 'GET, POST, PATCH, DELETE, OPTIONS';
const _allowedHeaders = 'Authorization, Content-Type';

/// Adds `Access-Control-Allow-*` headers for origins the operator has
/// explicitly named — off by default, and a no-op for any origin not in
/// [allowedOrigins] even when the set is non-empty (`specs/log-server-api`).
///
/// Placed ahead of rate limiting and principal resolution in the `Pipeline`
/// (`server.dart`): a preflight carries no `Authorization` and must not
/// spend a rate-limit bucket token or be treated as an unauthenticated
/// request, so a matching preflight is answered here and never reaches
/// either. A real request's response — success or error, since
/// `errorHandlingMiddleware` sits inside this middleware in the pipeline —
/// gets the header added on the way back out, because a browser needs it on
/// the error response itself to let the page read a 401 or 500.
///
/// Matching is exact string equality against the `Origin` header, never a
/// wildcard: the header is already a normalized `scheme://host[:port]`, so
/// asking the operator to list it verbatim keeps the allow-list a literal,
/// greppable value with no hidden normalization to get wrong.
Middleware corsMiddleware(Set<String> allowedOrigins) {
  return (Handler innerHandler) {
    return (Request request) async {
      final origin = request.headers['origin'];
      if (origin == null || !allowedOrigins.contains(origin)) {
        return innerHandler(request);
      }

      if (request.method == 'OPTIONS' &&
          request.headers.containsKey('access-control-request-method')) {
        return Response(
          204,
          headers: {
            'Access-Control-Allow-Origin': origin,
            'Access-Control-Allow-Methods': _allowedMethods,
            'Access-Control-Allow-Headers': _allowedHeaders,
            'Vary': 'Origin',
          },
        );
      }

      final response = await innerHandler(request);
      // `Response.change` merges the given headers into the existing ones
      // rather than replacing them — exactly what's wanted here, since the
      // handler's own headers (`content-type` and the like) must survive.
      return response.change(
        headers: {'Access-Control-Allow-Origin': origin, 'Vary': 'Origin'},
      );
    };
  };
}
