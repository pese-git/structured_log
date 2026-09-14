import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:structured_log_server/src/auth/identity_provider.dart';

/// Builds a [Request] as if it had already passed [authMiddleware]
/// (`lib/src/http/auth_middleware.dart`) and `shelf_router`'s path-param
/// matching — route handlers are tested directly, without a real HTTP
/// server or router in front of them.
Request authenticatedRequest(
  String method,
  String url, {
  required List<EffectiveRole> roles,
  int userId = 1,
  String username = 'alice',
  Map<String, String> params = const {},
  Object? jsonBody,
}) {
  return Request(
    method,
    Uri.parse(url),
    body: jsonBody == null ? null : jsonEncode(jsonBody),
    context: {
      'structured_log_server.verifiedIdentity': VerifiedIdentity(
        userId: userId,
        username: username,
        roles: roles,
      ),
      'shelf_router/params': params,
    },
  );
}

Future<Map<String, Object?>> decodeJson(Response response) async {
  final body = await response.readAsString();
  return jsonDecode(body) as Map<String, Object?>;
}
