import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:structured_log_admin_ui/structured_log_admin_ui.dart';

import '../../../l10n/formatting.dart';
import '../../../l10n/l10n.dart';
import '../../../shared/api/dto/user_dto.dart';
import '../../audit/presentation/audit_failure_text.dart' show formatAuditTime;
import '../../resources/presentation/resources_section.dart'
    show ResourceBreadcrumb;
import 'user_actions.dart';
import 'user_failure_text.dart';
import 'users_cubit.dart';

/// One user: profile, security, the roles they hold, and their most recent
/// acts in the audit journal (`UserDetail.dc.html`).
///
/// **Admin only**, and unconditionally so — unlike the mockup, which also
/// draws an `owner` viewing mode (read-only, a warning banner explaining why
/// editing is greyed out). Nothing else reaches this page: `UsersPage` is
/// offered by `HomeShell` only to a reader whose token claims the global
/// admin role, and every action here refuses with 403 for anyone else. So
/// only the mockup's `admin` variant is built — the primary-admin banner and
/// action gating below is the entire remaining difference this screen has to
/// account for.
///
/// Two more mockup rows are dropped for the same reason as the dashboard's:
/// no server response carries them. `UserDto.email`/`emailVerifiedAt` exist
/// on the wire but nothing ever populates them — `CreateUserDialog` has no
/// email field — so the profile card shows «—» rather than fabricating a
/// verified state; and "Последний вход"/"Активные сессии" are dropped
/// entirely, since the server tracks no session or login-IP history per
/// user (only per audit event, which is a different, not-per-session
/// record).
class UserDetailPage extends StatefulWidget {
  final UserDto user;
  final VoidCallback onBack;
  final VoidCallback onEdit;
  final VoidCallback onOpenAudit;

  const UserDetailPage({
    super.key,
    required this.user,
    required this.onBack,
    required this.onEdit,
    required this.onOpenAudit,
  });

  @override
  State<UserDetailPage> createState() => _UserDetailPageState();
}

class _UserDetailPageState extends State<UserDetailPage> {
  // Captured once, in `initState`, rather than `context.read` inside
  // `dispose()` — by then this page is already deactivated (`UsersSection`'s
  // `_go` swaps the whole subtree in one frame), and Provider refuses to
  // look up an ancestor through a context in that state.
  late final UsersCubit _cubit;

  @override
  void initState() {
    super.initState();
    _cubit = context.read<UsersCubit>();
    _cubit.loadRoleAssignments(widget.user.id);
    _cubit.loadRecentAudit(widget.user.id);
  }

  @override
  void dispose() {
    _cubit.clearActionFailure();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<UsersCubit, UsersState>(
      builder: (context, state) {
        // Looked up by id on every rebuild rather than trusting `widget.user`
        // — that copy is the snapshot the reader tapped in the list, and
        // this page outlives a single dialog, so an edit or a block/unblock
        // made from here must show up on itself, not just on the list
        // behind it. Falls back to the snapshot only if the id has somehow
        // dropped out of the loaded page (defensive, should not happen: a
        // delete from this page navigates away instead of leaving it here).
        final user = state.users.firstWhere(
          (u) => u.id == widget.user.id,
          orElse: () => widget.user,
        );

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AdminSpacing.x24,
            AdminSpacing.x18,
            AdminSpacing.x24,
            AdminSpacing.x24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(user: user, onBack: widget.onBack, onEdit: widget.onEdit),
              if (state.actionFailure != null) ...[
                const SizedBox(height: AdminSpacing.x14),
                AdminBanner(
                  message: describeUserFailure(
                    context.l10n,
                    state.actionFailure!,
                  ),
                  tone: AdminBannerTone.error,
                ),
              ],
              if (user.isPrimaryAdmin) ...[
                const SizedBox(height: AdminSpacing.x14),
                AdminBanner(message: context.l10n.usersPrimaryAdminBanner),
              ],
              const SizedBox(height: AdminSpacing.x24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Profile(user: user),
                        const SizedBox(height: AdminSpacing.x14),
                        _Security(user: user),
                      ],
                    ),
                  ),
                  const SizedBox(width: AdminSpacing.x14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Roles(user: user, state: state),
                        const SizedBox(height: AdminSpacing.x14),
                        _RecentAudit(
                          state: state,
                          onOpenAudit: widget.onOpenAudit,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  final UserDto user;
  final VoidCallback onBack;
  final VoidCallback onEdit;

  const _Header({
    required this.user,
    required this.onBack,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);
    final name = user.displayName ?? user.username;
    final initials = name.isEmpty
        ? '?'
        : name.trim().split(RegExp(r'\s+')).take(2).map((w) => w[0]).join();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ResourceBreadcrumb(
          parts: [
            (label: context.l10n.usersPageTitle, onPressed: onBack),
            (label: name, onPressed: null),
          ],
        ),
        const SizedBox(height: AdminSpacing.x10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.accentTint,
                borderRadius: BorderRadius.circular(AdminRadius.pill),
              ),
              child: Text(
                initials.toUpperCase(),
                style: AdminTypography.sectionTitle.copyWith(
                  color: colors.accentDark,
                ),
              ),
            ),
            const SizedBox(width: AdminSpacing.x14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: AdminSpacing.x10,
                    runSpacing: AdminSpacing.x6,
                    children: [
                      Text(
                        name,
                        style: AdminTypography.pageTitle.copyWith(
                          color: colors.text,
                        ),
                      ),
                      AdminTag(label: user.username),
                      if (user.isDeleted)
                        AdminStatusTag(
                          label: context.l10n.usersStatusDeleted,
                          tone: AdminStatusTone.neutral,
                        )
                      else if (user.isBlocked)
                        AdminStatusTag(
                          label: context.l10n.usersStatusBlocked,
                          tone: AdminStatusTone.error,
                        )
                      else
                        AdminStatusTag(
                          label: context.l10n.usersStatusActive,
                          tone: AdminStatusTone.success,
                        ),
                      if (user.isPrimaryAdmin)
                        AdminTag(label: context.l10n.usersPrimaryAdmin),
                    ],
                  ),
                  const SizedBox(height: AdminSpacing.x6),
                  Text(
                    context.l10n.usersCreatedOn(
                      formatDate(context.l10n, user.createdAt),
                    ),
                    style: AdminTypography.bodySmall.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (!user.isDeleted) ...[
              const SizedBox(width: AdminSpacing.x10),
              AdminButton(
                label: context.l10n.usersEditBreadcrumb,
                icon: FluentIcons.edit,
                size: AdminButtonSize.dialog,
                onPressed: onEdit,
              ),
              const SizedBox(width: AdminSpacing.x10),
              AdminButton(
                label: user.isBlocked
                    ? context.l10n.usersUnblock
                    : context.l10n.usersBlock,
                size: AdminButtonSize.dialog,
                onPressed: () => toggleUserBlocked(
                  context,
                  context.read<UsersCubit>(),
                  user,
                ),
              ),
              if (!user.isPrimaryAdmin) ...[
                const SizedBox(width: AdminSpacing.x10),
                AdminButton(
                  label: context.l10n.usersDelete,
                  size: AdminButtonSize.dialog,
                  onPressed: () => deleteUser(
                    context,
                    context.read<UsersCubit>(),
                    user,
                    // Nothing is left to show on this page once the row is
                    // gone from `state.users` — back to the list.
                    onDeleted: onBack,
                  ),
                ),
              ],
            ],
          ],
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  final String title;
  final Widget child;

  const _Card({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);
    return Container(
      padding: const EdgeInsets.all(AdminSpacing.x18),
      decoration: BoxDecoration(
        color: colors.cardBg,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(AdminRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: AdminTypography.label.copyWith(color: colors.text),
          ),
          const SizedBox(height: AdminSpacing.x12),
          child,
        ],
      ),
    );
  }
}

class _Profile extends StatelessWidget {
  final UserDto user;

  const _Profile({required this.user});

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: context.l10n.usersProfileTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdminKeyValueRow(
            label: context.l10n.usersFieldUsername,
            value: user.username,
            monospaceValue: true,
          ),
          AdminKeyValueRow(
            label: context.l10n.usersFieldEmail,
            value: user.email ?? '—',
          ),
          AdminKeyValueRow(
            label: context.l10n.usersFieldDisplayName,
            value: user.displayName ?? '—',
          ),
          AdminKeyValueRow(
            label: context.l10n.usersFieldCreated,
            value: formatDate(context.l10n, user.createdAt),
          ),
        ],
      ),
    );
  }
}

class _Security extends StatelessWidget {
  final UserDto user;

  const _Security({required this.user});

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: context.l10n.usersSecurityTitle,
      child: AdminKeyValueRow(
        label: context.l10n.usersFieldPassword,
        value: user.mustChangePassword
            ? context.l10n.usersPasswordTemporary
            : context.l10n.usersPasswordSetByUser,
      ),
    );
  }
}

class _Roles extends StatelessWidget {
  final UserDto user;
  final UsersState state;

  const _Roles({required this.user, required this.state});

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);

    return _Card(
      title: context.l10n.usersRolesTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state.roleAssignments.isEmpty)
            Text(
              context.l10n.usersNoRoles,
              style: AdminTypography.bodySmall.copyWith(
                color: colors.textSecondary,
              ),
            )
          else
            for (final grant in state.roleAssignments) ...[
              AdminResourceRow(
                icon: FluentIcons.permissions,
                title: grant.role,
                subtitle: scopeLabelOf(context.l10n, grant),
                actions: [
                  AdminButton(
                    label: context.l10n.usersRevoke,
                    size: AdminButtonSize.tonal,
                    onPressed: () => _revoke(context, grant),
                  ),
                ],
              ),
              const SizedBox(height: AdminSpacing.x10),
            ],
          const SizedBox(height: AdminSpacing.x6),
          _GrantRoleForm(userId: user.id),
        ],
      ),
    );
  }

  Future<void> _revoke(BuildContext context, RoleAssignmentDto grant) async {
    final cubit = context.read<UsersCubit>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AdminConfirmDialog(
        title: context.l10n.usersRevokeConfirmTitle(grant.role),
        message: context.l10n.usersRevokeConfirmMessage(
          scopeLabelOf(context.l10n, grant),
        ),
        confirmLabel: context.l10n.usersRevoke,
        cancelLabel: context.l10n.usersCancel,
        destructive: true,
        onConfirm: () => Navigator.of(dialogContext).pop(true),
        onCancel: () => Navigator.of(dialogContext).pop(false),
      ),
    );
    if (confirmed ?? false) cubit.revokeRole(grant.id, user.id);
  }
}

/// `grant.scopeType`/`scopeName`/`scopeId`, as one phrase — shared between
/// this page's roles card and its revoke confirmation.
String scopeLabelOf(AppLocalizations l10n, RoleAssignmentDto grant) {
  final name = grant.scopeName ?? '#${grant.scopeId}';
  return switch (grant.scopeType) {
    'global' => l10n.usersScopeGlobal,
    'group' => l10n.usersScopeGroupLabel(name),
    'project' => l10n.usersScopeProjectLabel(name),
    _ => grant.scopeType,
  };
}

/// The role-grant form under the roles card — moved here from the old
/// `EditUserDialog` verbatim, only the container around it changed.
class _GrantRoleForm extends StatefulWidget {
  final int userId;

  const _GrantRoleForm({required this.userId});

  @override
  State<_GrantRoleForm> createState() => _GrantRoleFormState();
}

class _GrantRoleFormState extends State<_GrantRoleForm> {
  var _role = 'user';
  var _scopeType = 'global';

  /// The picked group/project — `null` for `global` (no scope to pick) and
  /// also `null` whenever the picker's text no longer matches a selection
  /// (`AdminSearchPicker.onSelected`, cleared as soon as the reader edits
  /// what it shows).
  int? _scopeId;

  void _grant(BuildContext context) {
    if (_scopeType != 'global' && _scopeId == null) return;
    context.read<UsersCubit>().grantRole(
      userId: widget.userId,
      role: _role,
      scopeType: _scopeType,
      scopeId: _scopeId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<UsersCubit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _RolePicker(
                value: _role,
                onChanged: (value) => setState(() => _role = value),
              ),
            ),
            const SizedBox(width: AdminSpacing.x10),
            Expanded(
              child: _ScopeTypePicker(
                value: _scopeType,
                onChanged: (value) => setState(() {
                  _scopeType = value;
                  _scopeId = null;
                }),
              ),
            ),
          ],
        ),
        if (_scopeType != 'global') ...[
          const SizedBox(height: AdminSpacing.x10),
          AdminSearchPicker<int>(
            key: ValueKey(_scopeType),
            label: _scopeType == 'group'
                ? context.l10n.usersScopeTypeGroup
                : context.l10n.usersScopeTypeProject,
            placeholder: context.l10n.usersScopePickerPlaceholder,
            onSearch: (query) async {
              // Read before the awaits: the context may be gone by then.
              final truncated = context.l10n.commonSearchTruncated;
              if (_scopeType == 'group') {
                final page = await cubit.searchGroups(query);
                return [
                  for (final g in page.items)
                    AdminSearchPickerItem(value: g.id, label: g.name),
                  if (page.hasMore) AdminSearchPickerItem.hint(truncated),
                ];
              }
              final page = await cubit.searchProjects(query);
              return [
                for (final p in page.items)
                  AdminSearchPickerItem(value: p.id, label: p.name),
                if (page.hasMore) AdminSearchPickerItem.hint(truncated),
              ];
            },
            onSelected: (item) => setState(() => _scopeId = item?.value),
          ),
        ],
        const SizedBox(height: AdminSpacing.x10),
        Align(
          alignment: Alignment.centerRight,
          child: AdminButton(
            label: context.l10n.usersGrantRole,
            size: AdminButtonSize.tonal,
            onPressed: () => _grant(context),
          ),
        ),
      ],
    );
  }
}

class _RolePicker extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _RolePicker({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return ComboBox<String>(
      value: value,
      isExpanded: true,
      items: [
        ComboBoxItem(value: 'admin', child: const Text('admin')),
        ComboBoxItem(value: 'owner', child: const Text('owner')),
        ComboBoxItem(value: 'user', child: const Text('user')),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

class _ScopeTypePicker extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _ScopeTypePicker({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return ComboBox<String>(
      value: value,
      isExpanded: true,
      items: [
        ComboBoxItem(value: 'global', child: const Text('global')),
        const ComboBoxItem(value: 'group', child: Text('group')),
        ComboBoxItem(value: 'project', child: const Text('project')),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

class _RecentAudit extends StatelessWidget {
  final UsersState state;
  final VoidCallback onOpenAudit;

  const _RecentAudit({required this.state, required this.onOpenAudit});

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);

    return _Card(
      title: context.l10n.usersRecentAuditTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state.loadingRecentAudit)
            const Center(child: AdminLoadingIndicator())
          else if (state.recentAudit.isEmpty)
            Text(
              context.l10n.usersNoAuditEvents,
              style: AdminTypography.bodySmall.copyWith(
                color: colors.textSecondary,
              ),
            )
          else
            for (final entry in state.recentAudit)
              Padding(
                padding: const EdgeInsets.only(bottom: AdminSpacing.x8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 112,
                      child: Text(
                        formatAuditTime(entry.createdAt),
                        style: AdminTypography.caption.copyWith(
                          color: colors.textSecondary,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    Expanded(child: AdminTag(label: entry.action)),
                  ],
                ),
              ),
          const SizedBox(height: AdminSpacing.x6),
          Align(
            alignment: Alignment.centerLeft,
            child: HyperlinkButton(
              onPressed: onOpenAudit,
              child: Text(
                context.l10n.usersOpenInAudit,
                style: AdminTypography.caption.copyWith(color: colors.accent),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
