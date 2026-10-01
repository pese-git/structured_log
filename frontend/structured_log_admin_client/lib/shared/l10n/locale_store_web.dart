import 'package:web/web.dart' as web;

import 'locale_controller.dart';

/// The browser's `localStorage`. A language is not a secret, and it has to
/// survive a reload, or the switcher would be undone by the next F5.
///
/// The tokens are the contrast: the access token lives one tab at a time in
/// `sessionStorage`, and the refresh token is not here at all when the server
/// can hold it in an `HttpOnly` cookie. This comment used to claim they never
/// came near `localStorage` on the strength of decision 20 — on the web they
/// did, because that is what `flutter_secure_storage` is there
/// (`add-refresh-token-cookie`).
LocaleStore createLocaleStore() => _WebLocaleStore();

class _WebLocaleStore implements LocaleStore {
  static const _key = 'structured_log.locale';

  @override
  String? read() {
    try {
      return web.window.localStorage.getItem(_key);
    } catch (_) {
      // Storage blocked (private mode, policy): the preference is optional.
      return null;
    }
  }

  @override
  void write(String? languageCode) {
    try {
      if (languageCode == null) {
        web.window.localStorage.removeItem(_key);
      } else {
        web.window.localStorage.setItem(_key, languageCode);
      }
    } catch (_) {
      // See [read].
    }
  }
}
