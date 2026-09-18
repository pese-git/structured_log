import 'package:fluent_ui/fluent_ui.dart';

import '../tokens/tokens.dart';

/// The flyout that opens from `AdminAppShell`'s account block — mirrors
/// `AccountMenu.dc.html`: a small profile header, then "Account settings"
/// and "Sign out" as two distinct, labelled actions. Replaces the block's old
/// single tap target, which opened account settings directly and buried
/// sign-out as a button inside that dialog.
class AdminAccountMenu extends StatelessWidget {
  final String accountName;
  final String accountRole;
  final VoidCallback onOpenAccountSettings;
  final VoidCallback onSignOut;
  final String accountSettingsLabel;
  final String signOutLabel;

  const AdminAccountMenu({
    super.key,
    required this.accountName,
    required this.accountRole,
    required this.onOpenAccountSettings,
    required this.onSignOut,
    this.accountSettingsLabel = 'Account settings',
    this.signOutLabel = 'Sign out',
  });

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);
    return FlyoutContent(
      color: colors.surface,
      padding: const EdgeInsets.all(AdminSpacing.x8),
      constraints: const BoxConstraints(minWidth: 236, maxWidth: 260),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AdminRadius.card),
        side: BorderSide(color: colors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AdminSpacing.x10,
              AdminSpacing.x8,
              AdminSpacing.x10,
              AdminSpacing.x12,
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.accentTint,
                    borderRadius: BorderRadius.circular(AdminRadius.pill),
                  ),
                  child: Text(
                    _initials(accountName),
                    style: AdminTypography.captionStrong.copyWith(
                      color: colors.accentDark,
                    ),
                  ),
                ),
                const SizedBox(width: AdminSpacing.x10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        accountName,
                        overflow: TextOverflow.ellipsis,
                        style: AdminTypography.label.copyWith(
                          color: colors.text,
                        ),
                      ),
                      Text(
                        accountRole,
                        overflow: TextOverflow.ellipsis,
                        style: AdminTypography.caption.copyWith(
                          color: colors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _divider(colors),
          const SizedBox(height: AdminSpacing.x4),
          _AccountMenuRow(
            icon: FluentIcons.settings,
            label: accountSettingsLabel,
            color: colors.text,
            hoverColor: colors.cardBg,
            onPressed: onOpenAccountSettings,
          ),
          const SizedBox(height: AdminSpacing.x4),
          _divider(colors),
          const SizedBox(height: AdminSpacing.x4),
          _AccountMenuRow(
            icon: FluentIcons.sign_out,
            label: signOutLabel,
            color: colors.errorFg,
            hoverColor: colors.errorBg,
            onPressed: onSignOut,
          ),
        ],
      ),
    );
  }

  Widget _divider(AdminColors colors) => Container(
        height: 1,
        color: colors.border,
        margin: const EdgeInsets.symmetric(horizontal: AdminSpacing.x4),
      );

  /// Up to two letters — same rule `AdminAppShell`'s account block uses for
  /// its own avatar, so the initials match between the trigger and the menu
  /// it opens.
  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'))
      ..removeWhere((p) => p.isEmpty);
    if (parts.isEmpty) return '';
    if (parts.length == 1) {
      return parts.first.characters.first.toUpperCase();
    }
    return (parts.first.characters.first + parts[1].characters.first)
        .toUpperCase();
  }
}

class _AccountMenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color hoverColor;
  final VoidCallback onPressed;

  const _AccountMenuRow({
    required this.icon,
    required this.label,
    required this.color,
    required this.hoverColor,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return HoverButton(
      onPressed: onPressed,
      builder: (context, states) => Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: AdminSpacing.x10),
        decoration: BoxDecoration(
          color: states.isHovered ? hoverColor : null,
          borderRadius: BorderRadius.circular(AdminRadius.control),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: AdminSpacing.x10),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: AdminTypography.bodySmall.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
