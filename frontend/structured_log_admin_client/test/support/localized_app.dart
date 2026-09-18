import 'package:fluent_ui/fluent_ui.dart';
import 'package:structured_log_admin_client/l10n/l10n.dart';
import 'package:structured_log_admin_ui/structured_log_admin_ui.dart';

/// The app shell every widget test hosts its screen in: the admin theme plus
/// the localization delegates the screens read their text through.
///
/// Russian by default, because the tests assert on the strings a screen shows
/// and those were written against the Russian text; pass `Locale('en')` to
/// exercise the English one.
Widget localizedApp({
  required Widget home,
  Locale locale = const Locale('ru'),
  bool dark = false,
}) {
  return FluentApp(
    theme: dark ? AdminTheme.dark() : AdminTheme.light(),
    locale: locale,
    localizationsDelegates: adminLocalizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );
}
