import 'dart:convert';

import 'package:shelf/shelf.dart';

import '../errors.dart';

/// Parses [request]'s body as a JSON object, throwing `400 invalid_request`
/// for malformed JSON or a non-object top level (`log-server-api`'s general
/// error envelope covers every management endpoint's request validation).
Future<Map<String, Object?>> readJsonBody(Request request) async {
  final raw = await request.readAsString();
  Object? decoded;
  try {
    decoded = raw.isEmpty ? <String, Object?>{} : jsonDecode(raw);
  } on FormatException {
    throw ApiError.invalidRequest('Request body is not valid JSON.');
  }
  if (decoded is! Map<String, Object?>) {
    throw ApiError.invalidRequest('Request body must be a JSON object.');
  }
  return decoded;
}

/// Parses a path parameter as an integer id, throwing `404 not_found` if it
/// isn't one — an unparsable id can't address an existing row either way.
///
/// Takes the already-extracted [raw] value rather than the request plus a
/// parameter name: `shelf_router_generator` hands path parameters to the
/// handler as arguments and checks, at build time, that their names and count
/// match the route. Looking them up by string would reintroduce exactly the
/// typo this arrangement removes — a misspelled name used to mean a permanent
/// 404, not a compile error. [name] is only used for the message.
int parsePathId(String raw, String name) {
  final value = int.tryParse(raw);
  if (value == null) {
    throw ApiError.notFound('$name is not a valid id.');
  }
  return value;
}
