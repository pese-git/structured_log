import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:structured_log_admin_ui/structured_log_admin_ui.dart';

import '../../../l10n/l10n.dart';
import '../../../shared/auth/password_rejection.dart';
import '../domain/auth_failure.dart';
import 'change_password_cubit.dart';

/// Current password, new password, and the new one again.
///
/// The same three fields serve both ways in — the screen the server forces
/// and the one in settings — so they live here rather than twice
/// (`specs/admin-client-auth`).
class ChangePasswordForm extends StatefulWidget {
  /// What the submit button says. The forced screen continues into the app;
  /// settings simply saves.
  final String submitLabel;

  /// Whether the password being replaced is the temporary one an administrator
  /// set. The forced screen says so and points at the administrator; in
  /// account settings the current password is just the reader's own, and the
  /// same words would send them looking for someone who never gave it.
  final bool currentIsTemporary;

  const ChangePasswordForm({
    super.key,
    required this.submitLabel,
    this.currentIsTemporary = true,
  });

  @override
  State<ChangePasswordForm> createState() => _ChangePasswordFormState();
}

class _ChangePasswordFormState extends State<ChangePasswordForm> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _repeat = TextEditingController();

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _repeat.dispose();
    super.dispose();
  }

  void _submit() {
    context.read<ChangePasswordCubit>().submit(
      currentPassword: _current.text,
      newPassword: _next.text,
      repeatedPassword: _repeat.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ChangePasswordCubit, ChangePasswordState>(
      builder: (context, state) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (state.failure != null) ...[
              AdminBanner(
                message: _failureText(
                  context.l10n,
                  state.failure!,
                  currentIsTemporary: widget.currentIsTemporary,
                ),
                tone: AdminBannerTone.error,
              ),
              const SizedBox(height: AdminSpacing.x18),
            ],
            AdminTextField(
              label: widget.currentIsTemporary
                  ? context.l10n.authCurrentPasswordLabel
                  : context.l10n.authCurrentPasswordLabelOwn,
              controller: _current,
              obscure: true,
              autofocus: true,
              enabled: !state.submitting,
            ),
            const SizedBox(height: AdminSpacing.x14),
            AdminTextField(
              label: context.l10n.authNewPasswordLabel,
              controller: _next,
              obscure: true,
              enabled: !state.submitting,
            ),
            const SizedBox(height: AdminSpacing.x14),
            AdminTextField(
              label: context.l10n.authRepeatPasswordLabel,
              controller: _repeat,
              obscure: true,
              enabled: !state.submitting,
              onSubmitted: _submit,
              errorText: state.mismatch
                  ? context.l10n.authPasswordsMismatch
                  : null,
            ),
            const SizedBox(height: AdminSpacing.x18),
            AdminButton(
              label: widget.submitLabel,
              variant: AdminButtonVariant.accent,
              size: AdminButtonSize.dialog,
              onPressed: state.submitting ? null : _submit,
            ),
          ],
        );
      },
    );
  }

  static String _failureText(
    AppLocalizations l10n,
    AuthFailure failure, {
    required bool currentIsTemporary,
  }) => switch (failure) {
    // The server says `invalid_grant` here for one thing only, and it is not
    // about the session: the current password was wrong.
    InvalidCredentialsFailure() =>
      currentIsTemporary
          ? l10n.authChangeWrongCurrent
          : l10n.authChangeWrongCurrentOwn,
    RateLimitedAuthFailure(:final retryAfter) => l10n.authChangeRateLimited(
      retryAfter.inSeconds,
    ),
    NetworkAuthFailure() => l10n.authChangeNetwork,
    // Names the limit the server gave, so the fix is in the text.
    PasswordRejectedAuthFailure(:final details) =>
      describePasswordRejection(l10n, details) ?? l10n.authChangeUnexpected,
    EmailNotVerifiedFailure() ||
    UnexpectedAuthFailure() => l10n.authChangeUnexpected,
  };
}
