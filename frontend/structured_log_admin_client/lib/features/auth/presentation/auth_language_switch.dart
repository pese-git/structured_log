import 'package:fluent_ui/fluent_ui.dart';
import 'package:structured_log_admin_ui/structured_log_admin_ui.dart';

import '../../../l10n/l10n.dart';
import '../../../shared/l10n/locale_controller.dart';

/// "English · Русский" in the corner of the screens shown before the app.
///
/// Those screens are where the browser's guess about the language is most
/// likely to be wrong and least possible to correct: the switcher in account
/// settings is behind the sign-in they are asking for. No "browser default"
/// entry here — two languages, and the one showing is marked — because on a
/// screen someone is trying to get past, a third choice is only a question.
class AuthLanguageSwitch extends StatelessWidget {
  final LocaleController controller;

  const AuthLanguageSwitch({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);
    final l10n = context.l10n;
    // What is actually showing, whether it was chosen or resolved from the
    // browser.
    final current = Localizations.localeOf(context).languageCode;

    Widget option(String code, String name) {
      final selected = current == code;
      return HyperlinkButton(
        onPressed: selected ? null : () => controller.select(Locale(code)),
        child: Text(
          name,
          style: AdminTypography.bodySmall.copyWith(
            color: selected ? colors.text : colors.accent,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final locale in LocaleController.supported) ...[
          option(locale.languageCode, switch (locale.languageCode) {
            'ru' => l10n.shellLanguageRussian,
            'en' => l10n.shellLanguageEnglish,
            _ => locale.languageCode,
          }),
        ],
      ],
    );
  }
}
