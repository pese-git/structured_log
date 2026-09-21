import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:structured_log_server/src/auth/identity_provider.dart';
import 'package:structured_log_server/src/auth/principal.dart';
import 'package:structured_log_server/src/storage/database.dart';

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
    context: {'structured_log_server.principal': ProjectPrincipal(projectId)},
  );
}

Future<Map<String, Object?>> decodeJson(Response response) async {
  final body = await response.readAsString();
  return jsonDecode(body) as Map<String, Object?>;
}

/// Every audit record a route wrote, oldest first.
///
/// Route tests assert on these as well as on the response, because the two can
/// disagree in both directions and each way is a defect: a mutation that
/// answered 201 without leaving a record, and a record left behind by a request
/// that was refused.
Future<List<AuditLogEntry>> auditRows(StructuredLogDatabase db) =>
    db.select(db.auditLogEntries).get();

/// The `metadata` of one audit record, decoded.
Map<String, Object?> auditMetadata(AuditLogEntry row) =>
    jsonDecode(row.metadata) as Map<String, Object?>;
