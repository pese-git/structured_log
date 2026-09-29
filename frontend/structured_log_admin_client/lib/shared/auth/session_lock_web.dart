import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'session_lock.dart';

/// The Web Locks API: one exclusive lock per origin, held for as long as the
/// body runs, released even if the tab is closed mid-flight.
SessionLock createSessionLock() => _WebSessionLock();

class _WebSessionLock implements SessionLock {
  /// Scoped to this origin, and named for what it guards rather than for the
  /// app — two artifacts of this client on one origin would still be one
  /// session.
  static const _name = 'structured_log.token_refresh';

  @override
  Future<T> synchronized<T>(Future<T> Function() body) async {
    final locks = web.window.navigator.locks;
    // Locks are unavailable in an insecure context, and absent in older
    // browsers. Running unserialised is worse than serialised and better than
    // not running: the race it guards against is rare and self-announcing,
    // while refusing to renew would sign the reader out for certain.
    if (locks.isUndefinedOrNull) return body();

    // The body's own future is what the caller gets, not a Completer filled
    // from it. A Completer completed with an error before anyone listens
    // reports that error as uncaught — and nobody listens until the lock's
    // promise has come back through JS, which is well after. Every cold start
    // without a session did exactly that: the renewal's 400 surfaced as an
    // uncaught error in the console while the login screen worked as meant.
    late final Future<T> run;
    await locks
        .request(
          _name,
          ((JSAny? _) {
            run = body();
            // The promise this returns is what the browser holds the lock
            // for, so the lock spans the whole renewal rather than just its
            // scheduling. Listening here also marks the error handled.
            return run.then<void>((_) {}, onError: (Object _) {}).toJS;
          }).toJS,
        )
        .toDart;
    return run;
  }
}
