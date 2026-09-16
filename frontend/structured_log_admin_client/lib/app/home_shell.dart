import 'package:cherrypick/cherrypick.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:structured_log_admin_ui/structured_log_admin_ui.dart';

import '../features/auth/application/change_password.dart';
import '../features/auth/application/sign_out.dart';
import '../features/auth/di/auth_module.dart';
import '../features/auth/presentation/change_password_cubit.dart';
import '../features/auth/presentation/change_password_form.dart';
import '../features/log_browser/di/log_browser_module.dart';
import '../features/log_browser/presentation/log_browser_page.dart';
import '../features/log_browser/presentation/log_feed_bloc.dart';
import '../features/resources/di/resources_module.dart';
import '../features/resources/presentation/resources_section.dart';
import '../shared/auth/session_controller.dart';

/// What the application is once someone is signed in.
///
/// Two sections, as the artboards group them: administration (groups, and
/// through them projects and their keys) and logs. Users, teams, the audit
/// log and the dashboard appear on the artboards' nav and are not here — the
/// server has no endpoints behind them in this stage, and a nav item that
/// opens an empty screen is worse than one that is not offered.
class HomeShell extends StatefulWidget {
  final Scope scope;
  final SessionController session;

  const HomeShell({super.key, required this.scope, required this.session});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late final Scope _logScope = openLogBrowserScope(widget.scope);
  late final Scope _resourcesScope = openResourcesScope(widget.scope);
  late final Scope _authScope = openAuthScope(widget.scope);

  static const _groupsIndex = 0;
  static const _logsIndex = 1;

  var _navIndex = _groupsIndex;

  /// Changed when the log browser is opened from a project, which rebuilds it
  /// so it starts fresh rather than on whatever it was last showing.
  Key _logsKey = const ValueKey('logs');

  Future<void> _signOut() async {
    // The local session ends whatever the server answers, including when it
    // cannot be reached (`specs/admin-client-auth`), so there is nothing to
    // check here.
    await _authScope.resolve<SignOut>()();
    widget.session.signedOutNow();
  }

  void _openLogsFor(int projectId, String projectName) {
    setState(() {
      _navIndex = _logsIndex;
      _logsKey = ValueKey('logs-$projectId');
    });
  }

  @override
  Widget build(BuildContext context) {
    return AdminAppShell(
      // No title here: every screen behind this shell draws its own, with
      // its primary action on the same line — the artboards put "Создать
      // группу" beside "Группы" and the scope pill beside "Логи".
      title: null,
      accountName: 'Аккаунт',
      accountRole: 'Настройки',
      onAccountPressed: () => _openAccountSettings(context),
      selectedIndex: _navIndex,
      onSelected: (index) => setState(() => _navIndex = index),
      sections: const [
        AdminNavSection(
          title: 'Администрирование',
          items: [AdminNavItem(icon: FluentIcons.group, label: 'Группы')],
        ),
        AdminNavSection(
          title: 'Логи',
          items: [AdminNavItem(icon: FluentIcons.search, label: 'Поиск логов')],
        ),
      ],
      content: _navIndex == _groupsIndex
          ? ResourcesSection(scope: _resourcesScope, onOpenLogs: _openLogsFor)
          : BlocProvider(
              key: _logsKey,
              create: (_) => _logScope.resolve<LogFeedBloc>(),
              child: const LogBrowserPage(),
            ),
    );
  }

  Future<void> _openAccountSettings(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => BlocProvider(
        create: (_) => ChangePasswordCubit(
          changePassword: _authScope.resolve<ChangePassword>(),
          currentUsername: _authScope.resolve<CurrentUsername>(),
        )..loadUsername(),
        child: _AccountSettingsDialog(
          onClose: () => Navigator.of(dialogContext).pop(),
          onSignOut: () {
            Navigator.of(dialogContext).pop();
            _signOut();
          },
        ),
      ),
    );
  }
}

/// Account settings, as far as this stage's server allows.
///
/// `AccountSettings.dc.html` also shows the profile — username, email,
/// display name — and a way to delete the account. Neither is here: there is
/// no `GET /v1/users/me` and no `DELETE /v1/users/me` yet, so the only thing
/// this screen could honestly offer is the one it does.
///
/// Changing the password here does **not** end the session
/// (`specs/admin-client-auth`): the server retires the access token in hand,
/// and the refresh token renews it on the next request.
class _AccountSettingsDialog extends StatelessWidget {
  final VoidCallback onClose;
  final VoidCallback onSignOut;

  const _AccountSettingsDialog({
    required this.onClose,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);

    return BlocBuilder<ChangePasswordCubit, ChangePasswordState>(
      builder: (context, state) {
        return ContentDialog(
          constraints: const BoxConstraints(maxWidth: 460),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Настройки аккаунта',
                style: AdminTypography.sectionTitle.copyWith(
                  color: colors.text,
                ),
              ),
              if (state.username != null) ...[
                const SizedBox(height: AdminSpacing.x4),
                Text(
                  'Вошли как ${state.username}',
                  style: AdminTypography.bodySmall.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (state.changed)
                  const AdminBanner(
                    message:
                        'Пароль изменён. Сессия не прервана — можно '
                        'продолжать работу.',
                  )
                else ...[
                  Text(
                    'Сменить пароль',
                    style: AdminTypography.label.copyWith(color: colors.text),
                  ),
                  const SizedBox(height: AdminSpacing.x6),
                  Text(
                    'Потребуется текущий пароль. Смена не завершает вашу '
                    'сессию — вы останетесь в приложении.',
                    style: AdminTypography.caption.copyWith(
                      color: colors.textSecondary,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: AdminSpacing.x14),
                  const ChangePasswordForm(submitLabel: 'Сменить пароль'),
                ],
              ],
            ),
          ),
          actions: [
            AdminButton(
              label: 'Выйти из аккаунта',
              size: AdminButtonSize.dialog,
              onPressed: onSignOut,
            ),
            AdminButton(
              label: 'Закрыть',
              variant: AdminButtonVariant.accent,
              size: AdminButtonSize.dialog,
              onPressed: onClose,
            ),
          ],
        );
      },
    );
  }
}
