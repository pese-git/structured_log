import 'dart:convert';

import 'package:shelf/shelf.dart';

/// The general JSON error envelope `log-server-api` requires for every
/// rejected request outside `POST`/`DELETE /v1/auth/token` (those use the
/// RFC 6749 §5.2 shape instead — `TokenService`/its route handler render
/// that separately).
Response jsonError(int statusCode, String code, String message) {
  return Response(
    statusCode,
    body: jsonEncode({'error': code, 'message': message}),
    headers: {'content-type': 'application/json'},
  );
}

Response jsonOk(Object? body, {int statusCode = 200}) {
  return Response(
    statusCode,
    body: jsonEncode(body),
    headers: {'content-type': 'application/json'},
  );
}
