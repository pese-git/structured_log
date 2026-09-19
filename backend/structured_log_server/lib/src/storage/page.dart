/// One page of a cursor-paginated list, and whether another follows
/// (`log-server-pagination`).
class Page<T> {
  final List<T> items;

  /// The `id` to pass back as the cursor for the next page, or `null` on the
  /// last one.
  final int? nextCursor;

  const Page({required this.items, required this.nextCursor});
}

/// Turns rows read with one extra row of probe into a [Page].
///
/// The caller asks the store for `limit + 1` rows. That one row is never
/// shown; it only says there is more. The alternative is a `COUNT` query, or
/// handing out a cursor on every non-empty page — including the last, which
/// makes the client spend a request to learn the list is over.
///
/// [idOf] reads a row's `id`; the cursor is the last *shown* row's, not the
/// probe's.
Page<T> pageFromProbe<T>(List<T> rows, int limit, int Function(T) idOf) {
  final items = rows.take(limit).toList();
  return Page(
    items: items,
    nextCursor: rows.length > limit ? idOf(items.last) : null,
  );
}
