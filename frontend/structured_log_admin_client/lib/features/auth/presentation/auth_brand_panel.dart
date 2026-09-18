import 'package:fluent_ui/fluent_ui.dart';
import 'package:structured_log_admin_ui/structured_log_admin_ui.dart';

import '../../../l10n/l10n.dart';

/// The blue half of the screens shown before the app proper.
///
/// Shared by the login screen and the forced change-password screen, which
/// the artboards draw with the same panel (`Login.dc.html`,
/// `ForcePasswordChange.dc.html`).
class AuthBrandPanel extends StatelessWidget {
  /// The line at the foot of the panel. The login screen says what the
  /// product is; the forced change-password screen says why the rest of the
  /// app is closed — the artboards differ in exactly this one paragraph.
  final String description;

  const AuthBrandPanel({super.key, required this.description});

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);
    return Container(
      width: 440,
      color: colors.accent,
      padding: const EdgeInsets.all(40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(AdminRadius.control),
                ),
                child: Icon(
                  FluentIcons.text_document,
                  size: 22,
                  color: colors.accent,
                ),
              ),
              const SizedBox(height: AdminSpacing.x18),
              Text(
                'Structured Log',
                style: AdminTypography.pageTitle.copyWith(
                  color: colors.surface,
                ),
              ),
              const SizedBox(height: AdminSpacing.x4),
              Text(
                context.l10n.authBrandSubtitle,
                style: AdminTypography.body.copyWith(
                  color: colors.surface.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
          Text(
            description,
            style: AdminTypography.body.copyWith(
              color: colors.surface.withValues(alpha: 0.92),
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}
