import 'package:web/web.dart' as web;

import 'locale_controller.dart';

/// The browser's `localStorage`. A language is not a secret — unlike the
/// tokens, which never come near it (decision 20) — and it has to survive a
/// reload, or the switcher would be undone by the next F5.
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
