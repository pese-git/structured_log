import 'package:fluent_ui/fluent_ui.dart';

import 'app_localizations.dart';

export 'app_localizations.dart';

/// `context.l10n.someKey` — the generated [AppLocalizations] without the
/// `AppLocalizations.of(context)` ceremony at every call site.
extension AppLocalizationsContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// The delegates the app (and any test host) installs: the generated ones for
/// this client's own text, plus Fluent's, whose controls read theirs from it.
const adminLocalizationsDelegates = <LocalizationsDelegate<dynamic>>[
  ...AppLocalizations.localizationsDelegates,
  FluentLocalizations.delegate,
];
