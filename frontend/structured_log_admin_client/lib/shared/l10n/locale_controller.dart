import 'package:flutter/widgets.dart';

import '../../l10n/app_localizations.dart';

/// Where the chosen language is kept between visits.
abstract interface class LocaleStore {
  /// The stored language code, or `null` when nothing was chosen.
  String? read();

  /// Stores [languageCode]; `null` forgets the choice.
  void write(String? languageCode);
}

/// A [LocaleStore] that forgets when the process ends — the default off the
/// web, and what tests use.
class InMemoryLocaleStore implements LocaleStore {
  String? _value;

  InMemoryLocaleStore([this._value]);

  @override
  String? read() => _value;

  @override
  void write(String? languageCode) => _value = languageCode;
}

/// Which language the app is shown in.
///
/// [locale] is `null` until someone chooses one: the app then follows the
/// browser, resolving to English when the browser asks for a language the
/// client has no translation of. A choice is remembered in [store].
///
/// Outside the widget tree for the same reason [SessionController] is: the
/// language switcher lives deep in account settings, and the `FluentApp` that
/// must rebuild when it changes sits above the whole app.
class LocaleController extends ChangeNotifier {
  final LocaleStore _store;
  Locale? _locale;

  LocaleController({LocaleStore? store, Locale? initial})
    : _store = store ?? InMemoryLocaleStore() {
    _locale = initial ?? _fromCode(_store.read());
  }

  Locale? get locale => _locale;

  /// Languages the switcher offers, in the order it lists them.
  static List<Locale> get supported => AppLocalizations.supportedLocales;

  /// Chooses [locale]; `null` goes back to following the browser.
  void select(Locale? locale) {
    if (locale == _locale) return;
    _locale = locale;
    _store.write(locale?.languageCode);
    notifyListeners();
  }

  static Locale? _fromCode(String? code) {
    if (code == null) return null;
    for (final candidate in supported) {
      if (candidate.languageCode == code) return candidate;
    }
    return null;
  }
}
