import 'dart:convert';
import 'dart:typed_data' show BytesBuilder;

import 'package:shelf/shelf.dart';

import '../errors.dart';

/// Cap on a management-API or token-endpoint body. Those carry a handful of
/// short fields; only `POST /v1/logs` legitimately sends megabytes, and it has
/// its own configurable cap (`max-ingest-body-bytes`).
const maxSmallBodyBytes = 1024 * 1024;

/// The body exceeded the cap given to [readBodyCapped].
class BodyTooLargeException implements Exception {
  const BodyTooLargeException();
}

/// Reads [request]'s body as UTF-8 text, refusing more than [maxBytes].
///
/// The check happens while reading, not after: `Request.readAsString` buffers
/// everything before the caller can look at its length, so a cap applied to
/// its result has already spent the memory it was meant to protect. A declared
/// `Content-Length` over the cap is refused without reading a byte; a body
/// that is chunked or lies about its length is cut off as soon as it crosses
/// the line.
Future<String> readBodyCapped(Request request, int maxBytes) async {
  final declared = request.contentLength;
  if (declared != null && declared > maxBytes) {
    throw const BodyTooLargeException();
  }
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in request.read()) {
    bytes.add(chunk);
    if (bytes.length > maxBytes) throw const BodyTooLargeException();
  }
  return utf8.decode(bytes.takeBytes(), allowMalformed: true);
}

const _bodyTooLarge = ApiError(
  413,
  'payload_too_large',
  'Request body exceeds the configured size limit.',
);

/// Parses [request]'s body as a JSON object, throwing `400 invalid_request`
/// for malformed JSON or a non-object top level (`log-server-api`'s general
/// error envelope covers every management endpoint's request validation).
Future<Map<String, Object?>> readJsonBody(Request request) async {
  final String raw;
  try {
    raw = await readBodyCapped(request, maxSmallBodyBytes);
  } on BodyTooLargeException {
    throw _bodyTooLarge;
  }
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
