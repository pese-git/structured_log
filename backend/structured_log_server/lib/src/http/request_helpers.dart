import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

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

/// Reads path parameter [name] (`shelf_router`'s `Request.params`) as an
/// integer id, throwing `404 not_found` if it's missing or not a valid
/// integer — an unparsable id can't address an existing row either way.
int requirePathParamInt(Request request, String name) {
  final raw = request.params[name];
  final value = raw == null ? null : int.tryParse(raw);
  if (value == null) {
    throw ApiError.notFound('$name is not a valid id.');
  }
  return value;
}
