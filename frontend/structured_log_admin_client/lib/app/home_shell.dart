import 'dart:async';

import 'package:cherrypick/cherrypick.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fpdart/fpdart.dart' hide State;
import 'package:structured_log_admin_ui/structured_log_admin_ui.dart';

import '../features/auth/application/change_password.dart';
import '../features/auth/application/delete_account.dart';
import '../features/auth/application/sign_out.dart';
import '../features/auth/di/auth_module.dart';
import '../features/auth/presentation/change_password_cubit.dart';
import '../features/auth/presentation/change_password_form.dart';
import '../features/audit/di/audit_module.dart';
import '../features/audit/domain/audit_filter.dart';
import '../features/audit/presentation/audit_cubit.dart';
import '../features/audit/presentation/audit_page.dart';
import '../features/dashboard/presentation/dashboard_cubit.dart';
import '../features/dashboard/presentation/dashboard_page.dart';
import '../features/log_browser/di/log_browser_module.dart';
import '../features/log_browser/domain/log_scope.dart';
import '../features/log_browser/presentation/log_browser_page.dart';
import '../features/log_browser/presentation/log_feed_event.dart';
import '../features/log_browser/presentation/log_feed_bloc.dart';
import '../features/resources/application/manage_resources.dart';
import '../features/resources/di/resources_module.dart';
import '../features/resources/presentation/resources_section.dart';
import '../features/users/di/users_module.dart';
import '../features/users/presentation/sole_owner_conflict_dialog.dart';
import '../features/users/presentation/user_failure_text.dart'
    show blockingGroups;
import '../features/users/presentation/users_cubit.dart';
import '../features/users/presentation/users_section.dart';
import '../l10n/l10n.dart';
import '../shared/api/api_failure.dart';
import '../shared/auth/session_controller.dart';
import '../shared/l10n/locale_controller.dart';

/// The destinations the nav can offer, in the order it offers them.
///
/// An enum rather than bare indices, because [AdminAppShell.selectedIndex]
/// counts across every section's items flattened together — so a conditionally
/// present item silently shifts the ones after it. Keeping the destination and
/// its position in one list (see `_entries`) makes that impossible to get
/// wrong rather than merely documented.
///
/// [accountSettings] is not in that list — `AccountSettings.dc.html` has no
/// nav-rail entry of its own, only `AdminAccountMenu`'s "Настройки аккаунта"
/// reaches it, the same way [users]' detail/edit screens are reached without
/// one.
enum _Destination { dashboard, groups, users, audit, logs, accountSettings }

/// One nav item: which section it belongs to, how it is drawn, and where it
/// goes.
typedef _NavEntry = ({
  String section,
  AdminNavItem item,
  _Destination destination,
});

/// What the application is once someone is signed in.
///
/// Three sections, as the artboards group them: overview (the dashboard,
/// `admin` only — see `DashboardPage`'s doc comment for why the other roles
/// the mockup draws are not offered), administration (groups, and through
/// them projects and their keys — plus users and the audit log, both for an
/// administrator), and logs. Teams still appear on the artboards' nav and are
/// not here — the server has no endpoint behind them in this stage, and a nav
/// item that opens an empty screen is worse than one that is not offered.
class HomeShell extends StatefulWidget {
  final Scope scope;
  final SessionController session;

  /// The language switcher on the account settings page. Without one there is
  /// nothing to switch, and the page leaves the card out.
  final LocaleController? localeController;

  const HomeShell({
    super.key,
    required this.scope,
    required this.session,
    this.localeController,
  });

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

  @override
  void dispose() {
    // The shell's own feature scopes; `auth` belongs to `AuthGate`, which
    // opened it first and is still using it.
    unawaited(closeLogBrowserScope(widget.scope));
    unawaited(closeResourcesScope(widget.scope));
    unawaited(closeUsersScope(widget.scope));
    unawaited(closeAuditScope(widget.scope));
    super.dispose();
  }

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

  /// The dashboard's greeting, from the same unverified claim every other
  /// screen names the signed-in reader with
  /// (`shared/auth/access_token_claims.dart`).
  String? _username;

  /// Changed when the log browser is opened from a project, which rebuilds it
  /// so it starts fresh rather than on whatever it was last showing.
  Key _logsKey = const ValueKey('logs');

  /// The project the log browser opens on when it was reached from that
  /// project's own screen — "Open logs" there means these logs, not a list of
  /// scopes to choose from. `null` when reached from the nav.
  LogScope? _logsInitialScope;

  /// Same idea as [_logsKey], for jumping from the dashboard straight into a
  /// group (`_openGroupFor`) instead of the group list.
  Key _resourcesKey = const ValueKey('resources');
  ({int id, String name})? _resourcesInitialGroup;

  /// Same idea again, for `UserDetailPage`'s "Открыть в аудите" link
  /// (`_openAuditFor`) — a fresh `AuditCubit` filtered to one actor instead
  /// of the unfiltered journal.
  Key _auditKey = const ValueKey('audit');
  int? _auditInitialActorId;

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  Future<void> _loadRole() async {
    final isAdmin = await _authScope.resolve<IsGlobalAdmin>()();
    final username = await _authScope.resolve<CurrentUsername>()();
    if (!mounted) return;
    setState(() {
      _isAdmin = isAdmin;
      _username = username;
    });
  }

  /// The nav, flattened — the single list both the sections and the selected
  /// index are derived from.
  List<_NavEntry> _entries(AppLocalizations l10n) => [
    if (_isAdmin)
      (
        section: l10n.shellNavOverview,
        item: AdminNavItem(
          icon: FluentIcons.view_dashboard,
          label: l10n.shellNavDashboard,
        ),
        destination: _Destination.dashboard,
      ),
    (
      section: l10n.shellNavAdministration,
      item: AdminNavItem(icon: FluentIcons.group, label: l10n.shellNavGroups),
      destination: _Destination.groups,
    ),
    if (_isAdmin)
      (
        section: l10n.shellNavAdministration,
        item: AdminNavItem(icon: FluentIcons.people, label: l10n.shellNavUsers),
        destination: _Destination.users,
      ),
    if (_isAdmin)
      (
        section: l10n.shellNavAdministration,
        item: AdminNavItem(
          icon: FluentIcons.text_document,
          label: l10n.shellNavAudit,
        ),
        destination: _Destination.audit,
      ),
    (
      section: l10n.shellNavLogs,
      item: AdminNavItem(
        icon: FluentIcons.search,
        label: l10n.shellNavLogSearch,
      ),
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
      _logsInitialScope = LogScope.project(id: projectId, name: projectName);
    });
  }

  void _openGroupFor(int groupId, String groupName) {
    setState(() {
      _destination = _Destination.groups;
      _resourcesInitialGroup = (id: groupId, name: groupName);
      _resourcesKey = ValueKey('resources-group-$groupId');
    });
  }

  void _openAuditFor(int actorUserId) {
    setState(() {
      _destination = _Destination.audit;
      _auditInitialActorId = actorUserId;
      _auditKey = ValueKey('audit-actor-$actorUserId');
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final entries = _entries(l10n);
    final selected = entries.indexWhere((e) => e.destination == _destination);

    return AdminAppShell(
      // No title here: every screen behind this shell draws its own, with
      // its primary action on the same line — the artboards put "Создать
      // группу" beside "Группы" and the scope pill beside "Логи".
      title: null,
      // The claim, not a placeholder: the block used to read the same
      // "Аккаунт" / "Настройки" for every viewer, which is what made a
      // single ambiguous tap target tolerable in the first place — a real
      // name/role is worth a real menu (`AdminAccountMenu`).
      accountName: _username ?? l10n.shellAccountFallback,
      accountRole: _isAdmin ? l10n.shellRoleAdmin : l10n.shellRoleUser,
      accountSettingsLabel: l10n.shellAccountSettings,
      signOutLabel: l10n.shellSignOut,
      onOpenAccountSettings: _openAccountSettings,
      onSignOut: _signOut,
      // -1 both when a destination's item has gone away (must not read as
      // "none selected" in a widget that takes a plain int, so corrected to
      // 0) and when the destination is `accountSettings`, which has no item
      // to begin with — there `selected` is already -1 and stays -1, since
      // the mockup shows no rail item highlighted on that screen.
      selectedIndex: _destination == _Destination.accountSettings
          ? -1
          : (selected < 0 ? 0 : selected),
      onSelected: (index) =>
          setState(() => _destination = entries[index].destination),
      sections: _sectionsOf(entries),
      content: switch (_destination) {
        _Destination.dashboard => BlocProvider(
          create: (_) => DashboardCubit(
            _resourcesScope.resolve<ManageGroups>(),
            _resourcesScope.resolve<ManageProjects>(),
          )..load(),
          child: DashboardPage(
            username: _username ?? '',
            onOpenGroup: _openGroupFor,
            onOpenLogs: _openLogsFor,
            onShowAllGroups: () =>
                setState(() => _destination = _Destination.groups),
          ),
        ),
        _Destination.groups => ResourcesSection(
          key: _resourcesKey,
          scope: _resourcesScope,
          onOpenLogs: _openLogsFor,
          isAdmin: _isAdmin,
          initialGroup: _resourcesInitialGroup,
        ),
        _Destination.users => UsersSection(
          scope: _usersScope,
          onOpenAudit: _openAuditFor,
        ),
        _Destination.audit => BlocProvider(
          key: _auditKey,
          create: (_) {
            final cubit = _auditScope.resolve<AuditCubit>();
            final actorId = _auditInitialActorId;
            if (actorId == null) {
              cubit.load();
            } else {
              cubit.applyFilter(AuditFilter(actorUserId: actorId));
            }
            return cubit;
          },
          child: const AuditPage(),
        ),
        _Destination.logs => BlocProvider(
          key: _logsKey,
          create: (_) {
            final bloc = _logScope.resolve<LogFeedBloc>();
            if (_logsInitialScope case final scope?) {
              bloc.add(LogFeedEvent.scopeSelected(scope));
            }
            return bloc;
          },
          child: const LogBrowserPage(),
        ),
        _Destination.accountSettings => BlocProvider(
          create: (_) => ChangePasswordCubit(
            changePassword: _authScope.resolve<ChangePassword>(),
            currentUsername: _authScope.resolve<CurrentUsername>(),
          )..loadUsername(),
          child: _AccountSettingsPage(
            onDeleteAccount: () => _openDeleteAccount(context),
            localeController: widget.localeController,
          ),
        ),
      },
    );
  }

  void _openAccountSettings() =>
      setState(() => _destination = _Destination.accountSettings);

  /// `DeleteAccountDialog.dc.html`'s password prompt, then whichever of two
  /// things it led to: gone for good (sign out, the same way any other
  /// sign-out ends the session — deletion only revokes tokens server-side,
  /// it does not also and separately end this local one), or blocked by
  /// `409 sole_group_owner` (the same conflict `UsersPage`'s admin deletion
  /// already handles, reused here — see `SoleOwnerConflictDialog`'s doc
  /// comment for why [onGrantAccess] is conditional on [_isAdmin]).
  Future<void> _openDeleteAccount(BuildContext context) async {
    final result = await showDialog<Either<ApiFailure, Unit>>(
      context: context,
      builder: (_) => _DeleteAccountDialog(
        onSubmit: (password) => _authScope.resolve<DeleteAccount>()(password),
      ),
    );
    if (result == null || !context.mounted) return;
    await result.match(
      (failure) => _showDeleteAccountConflict(context, blockingGroups(failure)),
      (_) => _signOut(),
    );
  }

  Future<void> _showDeleteAccountConflict(
    BuildContext context,
    List<({int id, String name})> groups,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => SoleOwnerConflictDialog(
        ownAccount: true,
        groups: groups,
        onClose: () => Navigator.of(dialogContext).pop(),
        // Granting a role needs `admin` or that group's own `owner`
        // (`role_assignments_route.dart`'s `canCreateOrRevokeRoleAssignment`)
        // — an `owner` qualifies for their own group too, but this account
        // settings page has no per-group role check of its own the way the
        // admin Users screen does, so it only offers the button when the
        // broader `admin` grant is guaranteed to work.
        onGrantAccess: _isAdmin
            ? (group) async {
                Navigator.of(dialogContext).pop();
                if (!context.mounted) return;
                final cubit = _usersScope.resolve<UsersCubit>();
                await showGrantAccessToGroup(
                  context,
                  groupId: group.id,
                  groupName: group.name,
                  searchUsers: cubit.searchUsers,
                  searchTeams: (query) =>
                      cubit.searchTeamsOfGroup(group.id, query),
                  onGrant:
                      ({
                        required subjectType,
                        required subjectId,
                        required role,
                      }) => cubit.grantAccessToGroup(
                        groupId: group.id,
                        subjectType: subjectType,
                        subjectId: subjectId,
                        role: role,
                      ),
                );
                await cubit.close();
              }
            : null,
      ),
    );
  }
}

/// `DeleteAccountDialog.dc.html`: a password box added to
/// `AdminConfirmDialog`'s shape, exactly what its own doc comment says it is
/// for. Holds the field and the busy/error state `AdminConfirmDialog`
/// deliberately does not.
///
/// [onSubmit] answers `Right` (deleted) or `Left` — and this widget only
/// closes itself for those two outcomes that end the dialog either way:
/// success, or `409 sole_group_owner` (the caller opens
/// `SoleOwnerConflictDialog` next, which this dialog must get out of the way
/// for). Any other failure — wrong password, rate limited, offline — is
/// shown inline and leaves the field there to retry.
class _DeleteAccountDialog extends StatefulWidget {
  final Future<Either<ApiFailure, Unit>> Function(String password) onSubmit;

  const _DeleteAccountDialog({required this.onSubmit});

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _password = TextEditingController();
  var _submitting = false;
  String? _errorText;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _errorText = null;
    });
    final result = await widget.onSubmit(_password.text);
    if (!mounted) return;

    final closes = switch (result) {
      Right() => true,
      Left(value: ConflictFailure(code: 'sole_group_owner')) => true,
      Left() => false,
    };
    if (closes) {
      Navigator.of(context).pop(result);
      return;
    }
    setState(() {
      _submitting = false;
      _errorText = result.match(
        (failure) => _errorTextFor(context.l10n, failure),
        (_) => null,
      );
    });
  }

  String _errorTextFor(AppLocalizations l10n, ApiFailure failure) =>
      switch (failure) {
        UnauthorizedFailure(code: 'invalid_grant') =>
          l10n.shellDeleteInvalidPassword,
        ForbiddenFailure(code: 'cannot_delete_primary_admin') =>
          l10n.shellDeletePrimaryAdmin,
        RateLimitedFailure(:final retryAfter) => l10n.shellRateLimited(
          retryAfter.inSeconds,
        ),
        NetworkFailure() => l10n.shellNetworkFailure,
        _ => l10n.shellDeleteFailed,
      };

  @override
  Widget build(BuildContext context) {
    return AdminConfirmDialog(
      title: context.l10n.shellDeleteTitle,
      message: context.l10n.shellDeleteMessage,
      destructive: true,
      confirmLabel: context.l10n.shellDeleteConfirm,
      cancelLabel: context.l10n.commonCancel,
      onConfirm: _submitting ? null : _submit,
      onCancel: () => Navigator.of(context).pop(),
      content: AdminTextField(
        label: context.l10n.shellDeletePasswordLabel,
        controller: _password,
        obscure: true,
        autofocus: true,
        enabled: !_submitting,
        errorText: _errorText,
        onSubmitted: _submit,
      ),
    );
  }
}

/// Account settings, as far as this stage's server allows.
///
/// A page (`AccountSettings.dc.html`), not a dialog — reached like any other
/// destination, through `HomeShell._destination`, just without a nav-rail
/// item pointing at it (see `_Destination.accountSettings`).
///
/// All three of the mockup's cards are here now: "Профиль", "Безопасность"
/// and "Опасная зона" (`DELETE /v1/users/me` — see `DeleteAccount`). Email
/// and display name stay `—` in "Профиль": there is no `GET /v1/users/me`
/// in this stage, so username (read off the access token, same as
/// everywhere else this client names the signed-in reader) is the only one
/// of the mockup's three profile fields with anywhere to come from — an
/// honest blank beside the one that is real, not a row this build drops.
///
/// Changing the password here does **not** end the session
/// (`specs/admin-client-auth`): the server retires the access token in hand,
/// and the refresh token renews it on the next request. Deleting the
/// account, in contrast, ends it immediately (`HomeShell._openDeleteAccount`
/// signs out right after) — that is the whole point of the action.
///
/// No sign-out button here — it lives in `AdminAccountMenu`, the menu whose
/// "Настройки аккаунта" item opens this page, so there is exactly one place
/// to sign out from rather than one that also doubles as a detour through
/// the password form.
class _AccountSettingsPage extends StatefulWidget {
  final VoidCallback onDeleteAccount;
  final LocaleController? localeController;

  const _AccountSettingsPage({
    required this.onDeleteAccount,
    required this.localeController,
  });

  @override
  State<_AccountSettingsPage> createState() => _AccountSettingsPageState();
}

class _AccountSettingsPageState extends State<_AccountSettingsPage> {
  /// The mockup's "Безопасность" card is a closed summary row with a button,
  /// not an always-open form — the form is what pressing that button reveals.
  var _changingPassword = false;

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);
    final l10n = context.l10n;

    return BlocBuilder<ChangePasswordCubit, ChangePasswordState>(
      builder: (context, state) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AdminSpacing.x24,
            AdminSpacing.x18,
            AdminSpacing.x24,
            AdminSpacing.x24,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.shellSettingsTitle,
                  style: AdminTypography.pageTitle.copyWith(color: colors.text),
                ),
                const SizedBox(height: AdminSpacing.x18),
                if (state.username != null) ...[
                  _SectionLabel(l10n.shellSectionProfile, colors: colors),
                  const SizedBox(height: AdminSpacing.x10),
                  _Card(
                    colors: colors,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AdminKeyValueRow(
                          label: l10n.shellUsername,
                          value: state.username!,
                          monospaceValue: true,
                        ),
                        // No `GET /v1/users/me` in this stage — these two
                        // mockup fields have nowhere to come from. Shown
                        // rather than dropped, the way `UserDetailPage`
                        // shows a blank email as "—" for the same reason.
                        AdminKeyValueRow(label: l10n.shellEmail, value: '—'),
                        AdminKeyValueRow(
                          label: l10n.shellDisplayName,
                          value: '—',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AdminSpacing.x18),
                ],
                if (widget.localeController case final controller?) ...[
                  _SectionLabel(l10n.shellSectionLanguage, colors: colors),
                  const SizedBox(height: AdminSpacing.x10),
                  _Card(
                    colors: colors,
                    child: _LanguageRow(controller: controller),
                  ),
                  const SizedBox(height: AdminSpacing.x18),
                ],
                _SectionLabel(l10n.shellSectionSecurity, colors: colors),
                const SizedBox(height: AdminSpacing.x10),
                _Card(
                  colors: colors,
                  child: state.changed
                      ? AdminBanner(message: l10n.shellPasswordChanged)
                      : _changingPassword
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              l10n.shellPasswordHintForm,
                              style: AdminTypography.caption.copyWith(
                                color: colors.textSecondary,
                                height: 1.45,
                              ),
                            ),
                            const SizedBox(height: AdminSpacing.x14),
                            ChangePasswordForm(
                              currentIsTemporary: false,
                              offerKeepOtherSessions: true,
                              submitLabel: l10n.shellChangePassword,
                            ),
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l10n.shellChangePassword,
                                    style: AdminTypography.label.copyWith(
                                      color: colors.text,
                                    ),
                                  ),
                                  const SizedBox(height: AdminSpacing.x4),
                                  Text(
                                    l10n.shellPasswordHintRow,
                                    style: AdminTypography.caption.copyWith(
                                      color: colors.textSecondary,
                                      height: 1.45,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: AdminSpacing.x14),
                            AdminButton(
                              label: l10n.shellChangePassword,
                              onPressed: () =>
                                  setState(() => _changingPassword = true),
                            ),
                          ],
                        ),
                ),
                const SizedBox(height: AdminSpacing.x18),
                _SectionLabel(
                  l10n.shellSectionDanger,
                  colors: colors,
                  color: colors.errorFg,
                ),
                const SizedBox(height: AdminSpacing.x10),
                _Card(
                  colors: colors,
                  borderColor: colors.errorFg,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.shellDeleteAccountTitle,
                              style: AdminTypography.label.copyWith(
                                color: colors.text,
                              ),
                            ),
                            const SizedBox(height: AdminSpacing.x4),
                            Text(
                              l10n.shellDeleteAccountText,
                              style: AdminTypography.caption.copyWith(
                                color: colors.textSecondary,
                                height: 1.45,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AdminSpacing.x14),
                      AdminButton(
                        label: l10n.shellDeleteAccountTitle,
                        variant: AdminButtonVariant.danger,
                        onPressed: widget.onDeleteAccount,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The small caption-weight heading above each card — "Профиль",
/// "Безопасность", "Опасная зона" — the mockup repeats at 14px/600 above
/// every card on the page. "Опасная зона" is the one mockup heading with its
/// own colour rather than the page's ink, hence [color].
class _SectionLabel extends StatelessWidget {
  final String text;
  final AdminColors colors;
  final Color? color;

  const _SectionLabel(this.text, {required this.colors, this.color});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AdminTypography.label.copyWith(color: color ?? colors.text),
    );
  }
}

/// The bordered ground every card on `AccountSettings.dc.html` sits on —
/// same recipe as the quota card on `ProjectDetailPage`. "Опасная зона"'s
/// card takes its border in the error colour instead ([borderColor]), the
/// one visual departure the mockup gives that card.
class _Card extends StatelessWidget {
  final AdminColors colors;
  final Widget child;
  final Color? borderColor;

  const _Card({required this.colors, required this.child, this.borderColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AdminSpacing.x18),
      decoration: BoxDecoration(
        color: colors.cardBg,
        border: Border.all(color: borderColor ?? colors.border),
        borderRadius: BorderRadius.circular(AdminRadius.card),
      ),
      child: child,
    );
  }
}

/// The language switcher: a hint on the left, the choice on the right — the
/// same row shape as the other cards on this page.
///
/// "Browser default" is a real choice, not the absence of one: it is what puts
/// a person back to following the browser after they tried a language.
class _LanguageRow extends StatelessWidget {
  final LocaleController controller;

  const _LanguageRow({required this.controller});

  static const _system = 'system';

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);
    final l10n = context.l10n;

    // Names are written in their own language, whichever one is showing:
    // someone who landed on a language they cannot read must still be able to
    // find their own.
    String nameOf(Locale locale) => switch (locale.languageCode) {
      'ru' => l10n.shellLanguageRussian,
      'en' => l10n.shellLanguageEnglish,
      _ => locale.languageCode,
    };

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              l10n.shellLanguageHint,
              style: AdminTypography.caption.copyWith(
                color: colors.textSecondary,
                height: 1.45,
              ),
            ),
          ),
          const SizedBox(width: AdminSpacing.x14),
          SizedBox(
            width: 200,
            child: ComboBox<String>(
              isExpanded: true,
              value: controller.locale?.languageCode ?? _system,
              items: [
                ComboBoxItem(
                  value: _system,
                  child: Text(l10n.shellLanguageSystem),
                ),
                for (final locale in LocaleController.supported)
                  ComboBoxItem(
                    value: locale.languageCode,
                    child: Text(nameOf(locale)),
                  ),
              ],
              onChanged: (code) => controller.select(
                code == null || code == _system ? null : Locale(code),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
