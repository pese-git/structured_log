import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:structured_log_admin_ui/structured_log_admin_ui.dart';

import 'auth_brand_panel.dart';
import 'change_password_cubit.dart';
import 'change_password_form.dart';

/// The screen the server puts in front of everything else while an account
/// still carries the password an administrator gave it.
///
/// It is not a dialog over the app: the app is not reachable. Every
/// management and query endpoint answers `403 must_change_password` until the
/// password is replaced, so the only two ways off this screen are changing it
/// and signing out (`specs/admin-client-auth`, `ForcePasswordChange.dc.html`).
///
/// This is also the very first thing a fresh deployment shows: the server
/// creates its first administrator with a generated password and that
/// password is temporary by construction (design.md decisions 42/49).
class ForcePasswordChangePage extends StatefulWidget {
  /// Raised once the password is changed — the gate is behind us and the app
  /// takes over. The session survives the change: the server retires the
  /// access token in hand, and the refresh token renews it on the next
  /// request.
  final VoidCallback onChanged;

  final VoidCallback onSignOut;

  const ForcePasswordChangePage({
    super.key,
    required this.onChanged,
    required this.onSignOut,
  });

  @override
  State<ForcePasswordChangePage> createState() =>
      _ForcePasswordChangePageState();
}

class _ForcePasswordChangePageState extends State<ForcePasswordChangePage> {
  @override
  void initState() {
    super.initState();
    context.read<ChangePasswordCubit>().loadUsername();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);

    return ScaffoldPage(
      padding: EdgeInsets.zero,
      content: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: MediaQuery.sizeOf(context).width,
          ),
          child: SizedBox(
            width: 1160,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AuthBrandPanel(
                  description:
                      'Пароль, заданный администратором, всегда временный. '
                      'Пока он не сменён, остальные разделы приложения '
                      'закрыты — доступны только смена пароля и выход.',
                ),
                Expanded(
                  child: ColoredBox(
                    color: colors.surface,
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          vertical: AdminSpacing.x24,
                        ),
                        child: SizedBox(width: 340, child: _body(colors)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(AdminColors colors) {
    return BlocBuilder<ChangePasswordCubit, ChangePasswordState>(
      builder: (context, state) {
        if (state.changed) return _Changed(onContinue: widget.onChanged);

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(FluentIcons.lock, size: 22, color: colors.accent),
                const SizedBox(width: AdminSpacing.x12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Смените пароль',
                        style: AdminTypography.sectionTitle.copyWith(
                          color: colors.text,
                        ),
                      ),
                      const SizedBox(height: AdminSpacing.x6),
                      Text(
                        'Ваш пароль задал администратор, поэтому он считается '
                        'временным. Пока он не изменён, остальные разделы '
                        'недоступны.',
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
            const SizedBox(height: AdminSpacing.x24),
            const ChangePasswordForm(
              submitLabel: 'Сменить пароль и продолжить',
            ),
            const SizedBox(height: AdminSpacing.x18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    state.username == null
                        ? 'Вошли в систему'
                        : 'Вошли как ${state.username}',
                    style: AdminTypography.caption.copyWith(
                      color: colors.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                HyperlinkButton(
                  onPressed: widget.onSignOut,
                  child: Text(
                    'Выйти',
                    style: AdminTypography.caption.copyWith(
                      color: colors.accent,
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _Changed extends StatelessWidget {
  final VoidCallback onContinue;

  const _Changed({required this.onContinue});

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(FluentIcons.completed, size: 28, color: colors.successFg),
        const SizedBox(height: AdminSpacing.x14),
        Text(
          'Пароль изменён',
          textAlign: TextAlign.center,
          style: AdminTypography.sectionTitle.copyWith(color: colors.text),
        ),
        const SizedBox(height: AdminSpacing.x8),
        Text(
          'Временный пароль больше не действует. Остальные разделы приложения '
          'снова доступны.',
          textAlign: TextAlign.center,
          style: AdminTypography.bodySmall.copyWith(
            color: colors.textSecondary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: AdminSpacing.x24),
        AdminButton(
          label: 'Перейти в приложение',
          variant: AdminButtonVariant.accent,
          size: AdminButtonSize.dialog,
          onPressed: onContinue,
        ),
      ],
    );
  }
}
