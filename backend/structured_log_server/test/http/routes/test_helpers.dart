import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:structured_log_server/src/auth/identity_provider.dart';
import 'package:structured_log_server/src/auth/principal.dart';

/// Builds a [Request] as if it had already passed `principalMiddleware`
/// (`lib/src/http/principal_middleware.dart`) as a user, and `shelf_router`'s
/// path-param matching — route handlers are tested directly, without a real
/// HTTP server or router in front of them.
Request authenticatedRequest(
  String method,
  String url, {
  required List<EffectiveRole> roles,
  int userId = 1,
  String username = 'alice',
  Map<String, String> params = const {},
  bool mustChangePassword = false,
  Object? jsonBody,
}) {
  return Request(
    method,
    Uri.parse(url),
    body: jsonBody == null ? null : jsonEncode(jsonBody),
    context: {
      'structured_log_server.principal': UserPrincipal(
        VerifiedIdentity(
          userId: userId,
          username: username,
          roles: roles,
          mustChangePassword: mustChangePassword,
        ),
      ),
      'shelf_router/params': params,
    },
  );
}

/// The ingestion counterpart of [authenticatedRequest]: a request as if it
/// had passed `principalMiddleware` carrying a valid project secret key.
Request projectKeyRequest(
  String method,
  String url, {
  required int projectId,
  Object? jsonBody,
}) {
  return Request(
    method,
    Uri.parse(url),
    body: jsonBody == null ? null : jsonEncode(jsonBody),
    context: {
      'structured_log_server.principal': ProjectPrincipal(projectId),
    },
  );
}

Future<Map<String, Object?>> decodeJson(Response response) async {
  final body = await response.readAsString();
  return jsonDecode(body) as Map<String, Object?>;
}
