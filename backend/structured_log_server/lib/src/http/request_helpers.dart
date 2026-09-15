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

/// Parses a form-encoded body, or `null` when it cannot be parsed.
///
/// Returns rather than throws because the only endpoints that take a form —
/// the token ones — answer in the RFC 6749 shape rather than this API's
/// general envelope (`design.md` decision 10), so the caller builds the error.
///
/// `Uri.splitQueryString` throws on illegal percent encoding, which is
/// unauthenticated input arriving at an unauthenticated endpoint: without this
/// the server answers 500 and writes a stack trace for anything malformed sent
/// its way.
Map<String, String>? tryParseFormBody(String raw) {
  try {
    return Uri.splitQueryString(raw);
  } on ArgumentError {
    return null;
  } on FormatException {
    return null;
  }
}

/// Parses [request]'s body as a JSON array, throwing `400 invalid_request`
/// for malformed JSON or a non-array top level — the ingest endpoint's
/// counterpart to [readJsonBody].
Future<List<Object?>> readJsonArrayBody(String raw) async {
  Object? decoded;
  try {
    decoded = raw.isEmpty ? <Object?>[] : jsonDecode(raw);
  } on FormatException {
    throw ApiError.invalidRequest('Request body is not valid JSON.');
  }
  if (decoded is! List) {
    throw ApiError.invalidRequest('Request body must be a JSON array.');
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
