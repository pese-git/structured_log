/// One page of a cursor-paginated server list (`log-server-pagination`) and
/// the means to ask for the next.
///
/// [nextCursor] is opaque: it is handed back to the server as received.
/// `null` means this was the last page — the server says so itself, so the
/// client never has to request an empty page to find out.
class CursorPage<T> {
  final List<T> items;
  final String? nextCursor;

  const CursorPage(this.items, this.nextCursor);

  bool get hasMore => nextCursor != null;
}
