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

  /// Whether to offer leaving the account's other devices signed in.
  ///
  /// Off on the forced screen, and that is not a detail of layout: the
  /// password being replaced there is one an administrator chose and handed
  /// over, so ending every session it could have opened is the only sensible
  /// reading — there is nothing to offer to keep.
  final bool offerKeepOtherSessions;

  const ChangePasswordForm({
    super.key,
    required this.submitLabel,
    this.currentIsTemporary = true,
    this.offerKeepOtherSessions = false,
  });

  @override
  State<ChangePasswordForm> createState() => _ChangePasswordFormState();
}

class _ChangePasswordFormState extends State<ChangePasswordForm> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _repeat = TextEditingController();

  /// Unticked: the reader has to ask for their other devices to stay in,
  /// rather than notice a tick that would have signed them out.
  var _keepOtherSessions = false;

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
      // Never true where the box is not offered: a screen that does not ask
      // must not answer on the reader's behalf.
      keepOtherSessions: widget.offerKeepOtherSessions && _keepOtherSessions,
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
            // Keyed for the same reason as the sign-in form's fields: three
            // `AdminTextField`s are indistinguishable to a driver otherwise,
            // and this is the screen where `keep_other_sessions` has to be
            // exercised against a real server rather than a mock.
            AdminTextField(
              key: const ValueKey('change-password-current'),
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
              key: const ValueKey('change-password-new'),
              label: context.l10n.authNewPasswordLabel,
              controller: _next,
              obscure: true,
              enabled: !state.submitting,
            ),
            const SizedBox(height: AdminSpacing.x14),
            AdminTextField(
              key: const ValueKey('change-password-repeat'),
              label: context.l10n.authRepeatPasswordLabel,
              controller: _repeat,
              obscure: true,
              enabled: !state.submitting,
              onSubmitted: _submit,
              errorText: state.mismatch
                  ? context.l10n.authPasswordsMismatch
                  : null,
            ),
            if (widget.offerKeepOtherSessions) ...[
              const SizedBox(height: AdminSpacing.x14),
              Checkbox(
                key: const ValueKey('change-password-keep-other-sessions'),
                checked: _keepOtherSessions,
                onChanged: state.submitting
                    ? null
                    : (value) =>
                          setState(() => _keepOtherSessions = value ?? false),
                content: Text(
                  context.l10n.authKeepOtherSessions,
                  style: AdminTypography.bodySmall,
                ),
              ),
            ],
            const SizedBox(height: AdminSpacing.x18),
            AdminButton(
              key: const ValueKey('change-password-submit'),
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
