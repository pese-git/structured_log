import '../errors.dart';

/// Page size when the caller does not ask for one (`log-server-pagination`).
const defaultPageSize = 50;

/// The largest page any list returns. A larger `limit` is brought down to
/// this rather than refused: a caller that does not know the ceiling is still
/// served, and the response stays bounded.
const maxPageSize = 200;

/// `limit` and `cursor` of a paginated list, already checked.
///
/// The cursor is opaque to clients — they hand back what the server gave them
/// — but on the server it is the `id` of the last row of the previous page.
typedef PageRequest = ({int limit, int? cursor});

/// Reads `limit` and `cursor` from [params] (`log-server-pagination`).
///
/// Everything wrong here is the caller's mistake, so it is a `400`: a
/// non-integer or non-positive `limit`, and a `cursor` that is not something
/// the server issued. Guessing ("treat `abc` as the default") would hide the
/// bug in the caller, and letting it through reached the storage layer as an
/// `assert` or a `FormatException` — a `500`.
///
/// Call it after the role check and before touching storage, so a caller
/// without access gets `403` whatever their parameters look like.
PageRequest parsePageRequest(Map<String, String> params) {
  final rawLimit = params['limit'];
  var limit = defaultPageSize;
  if (rawLimit != null) {
    final parsed = int.tryParse(rawLimit);
    if (parsed == null || parsed < 1) {
      throw ApiError.invalidRequest(
        'limit must be a positive integer.',
        details: {'field': 'limit', 'reason': 'invalid'},
      );
    }
    limit = parsed > maxPageSize ? maxPageSize : parsed;
  }

  final rawCursor = params['cursor'];
  int? cursor;
  if (rawCursor != null) {
    cursor = int.tryParse(rawCursor);
    if (cursor == null || cursor < 1) {
      throw ApiError.invalidRequest(
        'cursor is not a value this server issued.',
        details: {'field': 'cursor', 'reason': 'invalid'},
      );
    }
  }

  return (limit: limit, cursor: cursor);
}
