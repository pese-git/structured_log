import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:structured_log_admin_ui/structured_log_admin_ui.dart';

import '../../../shared/api/dto/user_dto.dart';
import '../../audit/presentation/audit_failure_text.dart' show formatAuditTime;
import '../../resources/presentation/resource_failure_text.dart'
    show formatDate;
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
                  message: describeUserFailure(state.actionFailure!),
                  tone: AdminBannerTone.error,
                ),
              ],
              if (user.isPrimaryAdmin) ...[
                const SizedBox(height: AdminSpacing.x14),
                const AdminBanner(
                  message:
                      'Это основная учётная запись администратора. Удалить '
                      'её нельзя — ни другому администратору, ни ей самой; '
                      'сервер отклонит такой запрос с кодом '
                      'cannot_delete_primary_admin.',
                ),
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
            (label: 'Пользователи', onPressed: onBack),
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
                        const AdminStatusTag(
                          label: 'Удалён',
                          tone: AdminStatusTone.neutral,
                        )
                      else if (user.isBlocked)
                        const AdminStatusTag(
                          label: 'Заблокирован',
                          tone: AdminStatusTone.error,
                        )
                      else
                        const AdminStatusTag(
                          label: 'Активен',
                          tone: AdminStatusTone.success,
                        ),
                      if (user.isPrimaryAdmin)
                        const AdminTag(label: 'Основной администратор'),
                    ],
                  ),
                  const SizedBox(height: AdminSpacing.x6),
                  Text(
                    'Создан ${formatDate(user.createdAt)}',
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
                label: 'Изменить',
                icon: FluentIcons.edit,
                size: AdminButtonSize.dialog,
                onPressed: onEdit,
              ),
              const SizedBox(width: AdminSpacing.x10),
              AdminButton(
                label: user.isBlocked ? 'Разблокировать' : 'Заблокировать',
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
                  label: 'Удалить',
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
      title: 'Профиль',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdminKeyValueRow(
            label: 'Имя пользователя',
            value: user.username,
            monospaceValue: true,
          ),
          AdminKeyValueRow(label: 'Email', value: user.email ?? '—'),
          AdminKeyValueRow(
            label: 'Отображаемое имя',
            value: user.displayName ?? '—',
          ),
          AdminKeyValueRow(label: 'Создан', value: formatDate(user.createdAt)),
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
      title: 'Безопасность',
      child: AdminKeyValueRow(
        label: 'Пароль',
        value: user.mustChangePassword
            ? 'Временный — потребует смены при следующем входе'
            : 'Задан самим пользователем',
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
      title: 'Роли',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state.roleAssignments.isEmpty)
            Text(
              'Ролей пока не выдано.',
              style: AdminTypography.bodySmall.copyWith(
                color: colors.textSecondary,
              ),
            )
          else
            for (final grant in state.roleAssignments) ...[
              AdminResourceRow(
                icon: FluentIcons.permissions,
                title: grant.role,
                subtitle: scopeLabelOf(grant),
                actions: [
                  AdminButton(
                    label: 'Отозвать',
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
        title: 'Отозвать роль «${grant.role}»?',
        message: 'Доступ (${scopeLabelOf(grant)}) будет отозван немедленно.',
        confirmLabel: 'Отозвать',
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
String scopeLabelOf(RoleAssignmentDto grant) {
  return switch (grant.scopeType) {
    'global' => 'вся система',
    'group' => 'группа: ${grant.scopeName ?? '#${grant.scopeId}'}',
    'project' => 'проект: ${grant.scopeName ?? '#${grant.scopeId}'}',
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
            label: _scopeType == 'group' ? 'Группа' : 'Проект',
            placeholder: 'Начните вводить название…',
            onSearch: (query) async {
              if (_scopeType == 'group') {
                final items = await cubit.searchGroups(query);
                return [
                  for (final g in items)
                    AdminSearchPickerItem(value: g.id, label: g.name),
                ];
              }
              final items = await cubit.searchProjects(query);
              return [
                for (final p in items)
                  AdminSearchPickerItem(value: p.id, label: p.name),
              ];
            },
            onSelected: (item) => setState(() => _scopeId = item?.value),
          ),
        ],
        const SizedBox(height: AdminSpacing.x10),
        Align(
          alignment: Alignment.centerRight,
          child: AdminButton(
            label: 'Выдать роль',
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
      items: const [
        ComboBoxItem(value: 'admin', child: Text('admin')),
        ComboBoxItem(value: 'owner', child: Text('owner')),
        ComboBoxItem(value: 'user', child: Text('user')),
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
      items: const [
        ComboBoxItem(value: 'global', child: Text('global')),
        ComboBoxItem(value: 'group', child: Text('group')),
        ComboBoxItem(value: 'project', child: Text('project')),
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
      title: 'Последние события аудита',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state.loadingRecentAudit)
            const Center(child: AdminLoadingIndicator())
          else if (state.recentAudit.isEmpty)
            Text(
              'Событий пока нет.',
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
                'Открыть в аудите с фильтром по этому пользователю',
                style: AdminTypography.caption.copyWith(color: colors.accent),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
