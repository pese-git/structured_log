import 'package:fluent_ui/fluent_ui.dart';
import 'package:structured_log_admin_ui/structured_log_admin_ui.dart';

import '../../../l10n/l10n.dart';

/// `Новый пользователь` — username, a temporary password, and an optional
/// display name. No `email` field: this stage's server does not accept one
/// (`CreateUserRequestDto`).
class CreateUserDialog extends StatefulWidget {
  final bool submitting;
  final String? errorText;
  final void Function(String username, String password, String? displayName)
  onCreate;
  final VoidCallback onCancel;

  const CreateUserDialog({
    super.key,
    required this.onCreate,
    required this.onCancel,
    this.submitting = false,
    this.errorText,
  });

  @override
  State<CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends State<CreateUserDialog> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _displayName = TextEditingController();

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _displayName.dispose();
    super.dispose();
  }

  void _submit() {
    final username = _username.text.trim();
    final password = _password.text;
    if (username.isEmpty || password.isEmpty) return;
    final displayName = _displayName.text.trim();
    widget.onCreate(
      username,
      password,
      displayName.isEmpty ? null : displayName,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);
    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 440),
      title: Text(
        context.l10n.usersCreateDialogTitle,
        style: AdminTypography.sectionTitle.copyWith(color: colors.text),
      ),
      // Scrolling for the reason every dialog in this app scrolls: a bare
      // `Column` inside `ContentDialog`'s loose `Flexible` takes the whole of
      // it (`resource_dialogs.dart`).
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
            AdminTextField(
              label: context.l10n.usersFieldUsername,
              controller: _username,
              autofocus: true,
            ),
            const SizedBox(height: AdminSpacing.x14),
            AdminTextField(
              label: context.l10n.usersFieldTemporaryPassword,
              controller: _password,
              obscure: true,
            ),
            const SizedBox(height: AdminSpacing.x14),
            AdminTextField(
              label: context.l10n.usersFieldDisplayNameOptional,
              controller: _displayName,
            ),
            const SizedBox(height: AdminSpacing.x10),
            Text(
              context.l10n.usersTemporaryPasswordHint,
              style: AdminTypography.caption.copyWith(
                color: colors.textSecondary,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
      actions: [
        AdminButton(
          label: context.l10n.usersCancel,
          size: AdminButtonSize.dialog,
          onPressed: widget.submitting ? null : widget.onCancel,
        ),
        AdminButton(
          label: context.l10n.usersCreateUser,
          variant: AdminButtonVariant.accent,
          size: AdminButtonSize.dialog,
          onPressed: widget.submitting ? null : _submit,
        ),
      ],
    );
  }
}
