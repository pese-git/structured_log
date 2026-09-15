import 'package:fluent_ui/fluent_ui.dart';

import '../atoms/atoms.dart';
import '../tokens/tokens.dart';

/// The shape of a confirmation, as `ConfirmDialog.dc.html` draws it.
///
/// A scaffold, not a flow: it renders the warning, whatever fields the caller
/// slots in, and two buttons — and reports which one was pressed. It never
/// sends anything, never closes itself and holds no busy state of its own, so
/// the same shape serves "revoke this key" and "delete this account, and here
/// is the password field that must be filled first".
class AdminConfirmDialog extends StatelessWidget {
  final String title;

  /// What will happen — stated plainly, including irreversibility.
  final String message;

  /// Fields the confirmation needs, e.g. a password box. Sits between the
  /// message and the buttons.
  final Widget? content;

  final String confirmLabel;
  final String cancelLabel;

  /// Paints the confirming button in the error colour and the header glyph in
  /// its tint. The artboards reserve this for actions that destroy something.
  final bool destructive;

  /// `null` leaves the confirming button disabled — how a caller expresses
  /// "the password field is still empty" without this widget knowing why.
  final VoidCallback? onConfirm;

  final VoidCallback onCancel;

  const AdminConfirmDialog({
    super.key,
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.onConfirm,
    required this.onCancel,
    this.cancelLabel = 'Отмена',
    this.content,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);
    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 420),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: destructive ? colors.errorBg : colors.cardBg,
                  borderRadius: BorderRadius.circular(AdminRadius.card),
                ),
                child: Icon(
                  destructive ? FluentIcons.warning : FluentIcons.info,
                  size: 20,
                  color: destructive ? colors.errorFg : colors.textSecondary,
                ),
              ),
              const SizedBox(width: AdminSpacing.x12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AdminTypography.subtitle.copyWith(
                        color: colors.text,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: AdminSpacing.x6),
                    Text(
                      message,
                      style: AdminTypography.bodySmall.copyWith(
                        color: colors.textSecondary,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (content != null) ...[
            const SizedBox(height: AdminSpacing.x18),
            content!,
          ],
        ],
      ),
      actions: [
        AdminButton(
          label: cancelLabel,
          onPressed: onCancel,
          size: AdminButtonSize.dialog,
        ),
        AdminButton(
          label: confirmLabel,
          onPressed: onConfirm,
          size: AdminButtonSize.dialog,
          variant: destructive
              ? AdminButtonVariant.danger
              : AdminButtonVariant.accent,
        ),
      ],
    );
  }
}
