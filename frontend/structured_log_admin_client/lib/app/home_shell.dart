import 'package:cherrypick/cherrypick.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:structured_log_admin_ui/structured_log_admin_ui.dart';

import '../features/auth/application/change_password.dart';
import '../features/auth/application/sign_out.dart';
import '../features/auth/di/auth_module.dart';
import '../features/auth/presentation/change_password_cubit.dart';
import '../features/auth/presentation/change_password_form.dart';
import '../features/audit/di/audit_module.dart';
import '../features/audit/presentation/audit_cubit.dart';
import '../features/audit/presentation/audit_page.dart';
import '../features/log_browser/di/log_browser_module.dart';
import '../features/log_browser/presentation/log_browser_page.dart';
import '../features/log_browser/presentation/log_feed_bloc.dart';
import '../features/resources/di/resources_module.dart';
import '../features/resources/presentation/resources_section.dart';
import '../features/users/di/users_module.dart';
import '../features/users/presentation/users_cubit.dart';
import '../features/users/presentation/users_page.dart';
import '../shared/auth/session_controller.dart';

/// The destinations the nav can offer, in the order it offers them.
///
/// An enum rather than bare indices, because [AdminAppShell.selectedIndex]
/// counts across every section's items flattened together — so a conditionally
/// present item silently shifts the ones after it. Keeping the destination and
/// its position in one list (see `_entries`) makes that impossible to get
/// wrong rather than merely documented.
enum _Destination { groups, users, audit, logs }

/// One nav item: which section it belongs to, how it is drawn, and where it
/// goes.
typedef _NavEntry = ({
  String section,
  AdminNavItem item,
  _Destination destination,
});

/// What the application is once someone is signed in.
///
/// Two sections, as the artboards group them: administration (groups, and
/// through them projects and their keys — plus users and the audit log, both
/// for an administrator) and logs. Teams and the dashboard still appear on
/// the artboards' nav and are not here — the server has no endpoints behind
/// them in this stage, and a nav item that opens an empty screen is worse
/// than one that is not offered.
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
  late final Scope _usersScope = openUsersScope(widget.scope);
  late final Scope _auditScope = openAuditScope(widget.scope);
  late final Scope _authScope = openAuthScope(widget.scope);

  var _destination = _Destination.groups;

  /// Whether to offer the audit section.
  ///
  /// Read once, from the access token in hand — there is no endpoint that
  /// reports the caller's own roles. It decides what is offered, never what is
  /// allowed; the screen behind it still gets whatever the server says
  /// (`shared/auth/access_token_claims.dart`).
  ///
  /// Starts `false` so the nav never flashes an item the reader may not have:
  /// appearing a frame later is better than appearing and vanishing.
  var _isAdmin = false;

  /// Changed when the log browser is opened from a project, which rebuilds it
  /// so it starts fresh rather than on whatever it was last showing.
  Key _logsKey = const ValueKey('logs');

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  Future<void> _loadRole() async {
    final isAdmin = await _authScope.resolve<IsGlobalAdmin>()();
    if (!mounted) return;
    setState(() => _isAdmin = isAdmin);
  }

  /// The nav, flattened — the single list both the sections and the selected
  /// index are derived from.
  List<_NavEntry> get _entries => [
    const (
      section: 'Администрирование',
      item: AdminNavItem(icon: FluentIcons.group, label: 'Группы'),
      destination: _Destination.groups,
    ),
    if (_isAdmin)
      const (
        section: 'Администрирование',
        item: AdminNavItem(icon: FluentIcons.people, label: 'Пользователи'),
        destination: _Destination.users,
      ),
    if (_isAdmin)
      const (
        section: 'Администрирование',
        item: AdminNavItem(icon: FluentIcons.text_document, label: 'Аудит'),
        destination: _Destination.audit,
      ),
    const (
      section: 'Логи',
      item: AdminNavItem(icon: FluentIcons.search, label: 'Поиск логов'),
      destination: _Destination.logs,
    ),
  ];

  /// Consecutive entries sharing a title become one section, which is what
  /// keeps the flattened order and the drawn order the same list.
  List<AdminNavSection> _sectionsOf(List<_NavEntry> entries) {
    final titles = <String>[];
    final items = <String, List<AdminNavItem>>{};
    for (final entry in entries) {
      if (!items.containsKey(entry.section)) titles.add(entry.section);
      items.putIfAbsent(entry.section, () => []).add(entry.item);
    }
    return [
      for (final title in titles)
        AdminNavSection(title: title, items: items[title]!),
    ];
  }

  Future<void> _signOut() async {
    // The local session ends whatever the server answers, including when it
    // cannot be reached (`specs/admin-client-auth`), so there is nothing to
    // check here.
    await _authScope.resolve<SignOut>()();
    widget.session.signedOutNow();
  }

  void _openLogsFor(int projectId, String projectName) {
    setState(() {
      _destination = _Destination.logs;
      _logsKey = ValueKey('logs-$projectId');
    });
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    final selected = entries.indexWhere((e) => e.destination == _destination);

    return AdminAppShell(
      // No title here: every screen behind this shell draws its own, with
      // its primary action on the same line — the artboards put "Создать
      // группу" beside "Группы" and the scope pill beside "Логи".
      title: null,
      accountName: 'Аккаунт',
      accountRole: 'Настройки',
      onAccountPressed: () => _openAccountSettings(context),
      // -1 cannot happen while every destination has an entry, but a
      // destination whose item has gone away must not read as "none selected"
      // in a widget that takes a plain int.
      selectedIndex: selected < 0 ? 0 : selected,
      onSelected: (index) =>
          setState(() => _destination = entries[index].destination),
      sections: _sectionsOf(entries),
      content: switch (_destination) {
        _Destination.groups => ResourcesSection(
          scope: _resourcesScope,
          onOpenLogs: _openLogsFor,
        ),
        _Destination.users => BlocProvider(
          create: (_) => _usersScope.resolve<UsersCubit>()..load(),
          child: const UsersPage(),
        ),
        _Destination.audit => BlocProvider(
          create: (_) => _auditScope.resolve<AuditCubit>()..load(),
          child: const AuditPage(),
        ),
        _Destination.logs => BlocProvider(
          key: _logsKey,
          create: (_) => _logScope.resolve<LogFeedBloc>(),
          child: const LogBrowserPage(),
        ),
      },
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
