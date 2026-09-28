import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:structured_log_admin_ui/structured_log_admin_ui.dart';
import '../../../../l10n/l10n.dart';

/// `Ключ создан` (`SecretKeyReveal.dc.html`).
///
/// The only place the value of a secret key is ever on screen. There is no
/// second chance: the server keeps a hash, and closing this dialog is the
/// moment the value stops existing
/// (`specs/admin-client-resource-management`).
class SecretKeyRevealDialog extends StatelessWidget {
  final String projectName;
  final String label;
  final String secret;
  final VoidCallback onClose;

  const SecretKeyRevealDialog({
    super.key,
    required this.projectName,
    required this.label,
    required this.secret,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);
    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 480),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(FluentIcons.completed, size: 18, color: colors.successFg),
              const SizedBox(width: AdminSpacing.x8),
              Text(
                context.l10n.resKeyCreated,
                style: AdminTypography.sectionTitle.copyWith(
                  color: colors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: AdminSpacing.x4),
          Text(
            context.l10n.resKeyRevealSubtitle(projectName, label),
            style: AdminTypography.bodySmall.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
      // Scrolling, like the quota dialogs above, and for two reasons at once.
      // A bare `Column` defaults to `MainAxisSize.max`, and `ContentDialog`
      // hands its content a *loose* `Flexible` — a maximum height, not a tight
      // one — so such a column takes the whole of it and the dialog stands as
      // tall as the window whatever it is holding. And a window short enough
      // that the content really does not fit should scroll rather than
      // overflow (`test/features/resources/dialog_layout_test.dart`).
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AdminBanner(
              message: context.l10n.resKeyRevealWarning,
              tone: AdminBannerTone.error,
            ),
            const SizedBox(height: AdminSpacing.x14),
            Container(
              padding: const EdgeInsets.all(AdminSpacing.x12),
              decoration: BoxDecoration(
                color: colors.cardBg,
                border: Border.all(color: colors.border),
                borderRadius: BorderRadius.circular(AdminRadius.control),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      secret,
                      style: AdminTypography.monoSmall.copyWith(
                        color: colors.text,
                      ),
                    ),
                  ),
                  const SizedBox(width: AdminSpacing.x8),
                  IconButton(
                    icon: const Icon(FluentIcons.copy, size: 16),
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: secret)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        AdminButton(
          label: context.l10n.resKeySavedClose,
          variant: AdminButtonVariant.accent,
          size: AdminButtonSize.dialog,
          onPressed: onClose,
        ),
      ],
    );
  }
}
