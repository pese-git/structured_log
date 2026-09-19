import 'package:structured_log_admin_client/shared/api/cursor_page.dart';

/// One page of [all] the way a fake repository can serve it: [limit] rows
/// (everything when it is `null`) from where [cursor] says, and a cursor for
/// the next page only while something follows.
///
/// The cursor is the index to continue from. That is the fake's own business —
/// the client treats it as opaque, and a test that read into it would be
/// testing the fake.
CursorPage<T> pageOf<T>(List<T> all, {int? limit, String? cursor}) {
  final start = cursor == null ? 0 : int.parse(cursor);
  final end = limit == null ? all.length : start + limit;
  return CursorPage(
    all.sublist(start, end.clamp(start, all.length)),
    end < all.length ? '$end' : null,
  );
}
