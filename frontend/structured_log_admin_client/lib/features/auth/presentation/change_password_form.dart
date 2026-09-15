import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:structured_log_admin_ui/structured_log_admin_ui.dart';

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

  const ChangePasswordForm({super.key, required this.submitLabel});

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
                message: _failureText(state.failure!),
                tone: AdminBannerTone.error,
              ),
              const SizedBox(height: AdminSpacing.x18),
            ],
            AdminTextField(
              label: 'Текущий (временный) пароль',
              controller: _current,
              obscure: true,
              autofocus: true,
              enabled: !state.submitting,
            ),
            const SizedBox(height: AdminSpacing.x14),
            AdminTextField(
              label: 'Новый пароль',
              controller: _next,
              obscure: true,
              enabled: !state.submitting,
            ),
            const SizedBox(height: AdminSpacing.x14),
            AdminTextField(
              label: 'Повторите новый пароль',
              controller: _repeat,
              obscure: true,
              enabled: !state.submitting,
              onSubmitted: _submit,
              errorText: state.mismatch ? 'Пароли не совпадают' : null,
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

  static String _failureText(AuthFailure failure) => switch (failure) {
    // The server says `invalid_grant` here for one thing only, and it is not
    // about the session: the current password was wrong.
    InvalidCredentialsFailure() =>
      'Текущий пароль неверен. Введите тот, который сообщил администратор.',
    RateLimitedAuthFailure(:final retryAfter) =>
      'Слишком много попыток. Попробуйте снова через ${retryAfter.inSeconds} с.',
    NetworkAuthFailure() => 'Сервер недоступен. Проверьте подключение.',
    EmailNotVerifiedFailure() ||
    UnexpectedAuthFailure() => 'Не удалось сменить пароль. Попробуйте ещё раз.',
  };
}
