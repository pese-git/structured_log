import 'package:fluent_ui/fluent_ui.dart';
import 'package:structured_log_admin_ui/structured_log_admin_ui.dart';
import '../../../../l10n/l10n.dart';

/// One field and a name for it. Used for the group, the team, and the secret
/// key, which the server asks nothing else about.
class NameDialog extends StatefulWidget {
  final String title;
  final String fieldLabel;
  final String confirmLabel;
  final String? description;

  /// The enclosing group, shown as a «Группа» tag above the field — the team
  /// this dialog also creates has one, the group this dialog creates does
  /// not (`CreateTeamDialog.dc.html` vs `Groups.dc.html`'s own dialog).
  final String? groupLabel;
  final bool submitting;
  final String? errorText;
  final ValueChanged<String> onSubmit;
  final VoidCallback onCancel;

  const NameDialog({
    super.key,
    required this.title,
    required this.fieldLabel,
    required this.confirmLabel,
    required this.onSubmit,
    required this.onCancel,
    this.description,
    this.groupLabel,
    this.submitting = false,
    this.errorText,
  });

  @override
  State<NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<NameDialog> {
  final _value = TextEditingController();

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);
    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 440),
      title: Text(
        widget.title,
        style: AdminTypography.sectionTitle.copyWith(color: colors.text),
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
            if (widget.errorText != null) ...[
              AdminBanner(
                message: widget.errorText!,
                tone: AdminBannerTone.error,
              ),
              const SizedBox(height: AdminSpacing.x14),
            ],
            if (widget.groupLabel != null) ...[
              Text(
                context.l10n.resGroup,
                style: AdminTypography.bodySmall.copyWith(color: colors.text),
              ),
              const SizedBox(height: AdminSpacing.x6),
              AdminTag(label: widget.groupLabel!),
              const SizedBox(height: AdminSpacing.x14),
            ],
            AdminTextField(
              label: widget.fieldLabel,
              controller: _value,
              autofocus: true,
              onSubmitted: () => widget.onSubmit(_value.text.trim()),
            ),
            if (widget.description != null) ...[
              const SizedBox(height: AdminSpacing.x10),
              Text(
                widget.description!,
                style: AdminTypography.caption.copyWith(
                  color: colors.textSecondary,
                  height: 1.45,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        AdminButton(
          label: context.l10n.resCancel,
          size: AdminButtonSize.dialog,
          onPressed: widget.submitting ? null : widget.onCancel,
        ),
        AdminButton(
          label: widget.confirmLabel,
          variant: AdminButtonVariant.accent,
          size: AdminButtonSize.dialog,
          onPressed: widget.submitting
              ? null
              : () => widget.onSubmit(_value.text.trim()),
        ),
      ],
    );
  }
}
