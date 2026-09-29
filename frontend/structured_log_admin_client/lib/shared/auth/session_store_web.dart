import 'package:web/web.dart' as web;

import 'session_store.dart';

/// The browser's `sessionStorage`: one copy per tab, cleared when the tab
/// closes, kept across a reload.
SessionStore createSessionStore() => _WebSessionStore();

class _WebSessionStore implements SessionStore {
  static const _key = 'structured_log.access_token';

  @override
  String? read() {
    try {
      return web.window.sessionStorage.getItem(_key);
    } catch (_) {
      // Storage blocked — private mode, or a policy that forbids it. Losing
      // the access token costs one refresh, so treat it as an empty tab
      // rather than as a failure the user has to see.
      return null;
    }
  }

  @override
  void write(String? value) {
    try {
      if (value == null) {
        web.window.sessionStorage.removeItem(_key);
      } else {
        web.window.sessionStorage.setItem(_key, value);
      }
    } catch (_) {
      // See [read]. A session that cannot be remembered still works; it just
      // renews once per tab.
    }
  }
}
