import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:structured_log_server/src/auth/identity_provider.dart';
import 'package:structured_log_server/src/auth/principal.dart';

/// Builds a [Request] as if it had already passed `principalMiddleware`
/// (`lib/src/http/principal_middleware.dart`) as a user.
///
/// Route tests send these through the feature's own generated `Router`
/// (`routes.router.call(...)`), so path parameters come out of the request
/// URL exactly as they do in production — there is nothing to fake.
Request authenticatedRequest(
  String method,
  String url, {
  required List<EffectiveRole> roles,
  int userId = 1,
  String username = 'alice',
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
