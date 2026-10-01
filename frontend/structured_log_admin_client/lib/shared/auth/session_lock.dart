export 'session_lock_io.dart'
    if (dart.library.js_interop) 'session_lock_web.dart';

/// Serialises token renewal across every tab of this origin.
///
/// The problem it solves exists only because the refresh token moved into an
/// `HttpOnly` cookie. A tab that has no access token of its own must renew to
/// get one, and two tabs starting together read the same cookie — the second
/// then presents a token the first has just spent. The server cannot tell
/// that from theft, and must not: it revokes the whole chain, and the reader
/// is signed out everywhere (`add-refresh-token-cookie/design.md`, decision
/// 7).
///
/// Settling it here rather than on the server is the point. On the server a
/// racing tab and a thief are the same request; in the browser they are not,
/// because both tabs belong to the same person and can simply take turns.
///
/// Holding the lock is not enough on its own: whoever waited has to re-read
/// the token before using it, since the winner has rotated it. That is the
/// caller's job, not this interface's.
abstract interface class SessionLock {
  Future<T> synchronized<T>(Future<T> Function() body);
}

/// Runs the body straight away.
///
/// For tests and for anything that is not a browser — there are no other tabs
/// to take turns with.
class NoSessionLock implements SessionLock {
  const NoSessionLock();

  @override
  Future<T> synchronized<T>(Future<T> Function() body) => body();
}
