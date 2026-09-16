import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:structured_log_admin_ui/structured_log_admin_ui.dart';

import '../../../shared/api/api_failure.dart';
import '../../../shared/api/dto/user_dto.dart';
import '../../resources/presentation/resource_failure_text.dart'
    show formatDate;
import 'user_dialogs.dart';
import 'user_failure_text.dart';
import 'users_cubit.dart';

/// The list of users, and the way to create, edit, block/unblock and delete
/// one (`Users.dc.html`).
///
/// Offered only to a reader whose access token carries the global admin
/// role — but that decides what to offer, never what to allow: the server
/// answers 403 to every one of these endpoints for anyone else, and this
/// screen renders that refusal rather than assuming it cannot happen
/// (`HomeShell._isAdmin`).
class UsersPage extends StatelessWidget {
  const UsersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);

    return BlocBuilder<UsersCubit, UsersState>(
      builder: (context, state) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AdminSpacing.x24,
            AdminSpacing.x18,
            AdminSpacing.x24,
            AdminSpacing.x24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Пользователи',
                      overflow: TextOverflow.ellipsis,
                      style: AdminTypography.pageTitle.copyWith(
                        color: colors.text,
                      ),
                    ),
                  ),
                  const SizedBox(width: AdminSpacing.x12),
                  AdminButton(
                    label: 'Создать пользователя',
                    icon: FluentIcons.add,
                    variant: AdminButtonVariant.accent,
                    size: AdminButtonSize.dialog,
                    onPressed: () => _create(context),
                  ),
                ],
              ),
              const SizedBox(height: AdminSpacing.x18),
              Expanded(child: _body(context, state)),
            ],
          ),
        );
      },
    );
  }

  Widget _body(BuildContext context, UsersState state) {
    if (state.loading) {
      return const Center(child: AdminLoadingIndicator());
    }
    if (state.failure != null && state.users.isEmpty) {
      return AdminEmptyState(
        icon: FluentIcons.error_badge,
        title: 'Не удалось загрузить пользователей',
        description: describeUserFailure(state.failure!),
      );
    }
    if (state.isEmpty) {
      return const AdminEmptyState(
        icon: FluentIcons.contact,
        title: 'Пользователей пока нет',
        description:
            'Здесь появятся учётные записи, как только вы создадите первую.',
      );
    }

    return ListView(
      children: [
        for (final user in state.users) ...[
          _UserRow(user: user),
          const SizedBox(height: AdminSpacing.x10),
        ],
        if (state.hasMore)
          Padding(
            padding: const EdgeInsets.all(AdminSpacing.x18),
            child: Center(
              child: state.loadingMore
                  ? const AdminLoadingIndicator()
                  : AdminButton(
                      label: 'Показать ещё',
                      icon: FluentIcons.chevron_down,
                      onPressed: context.read<UsersCubit>().loadMore,
                    ),
            ),
          ),
      ],
    );
  }

  Future<void> _create(BuildContext context) async {
    final cubit = context.read<UsersCubit>();
    var closing = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => BlocProvider.value(
        value: cubit,
        child: BlocBuilder<UsersCubit, UsersState>(
          builder: (builderContext, state) {
            // Once only — see the identical guard in `GroupsPage._create` for
            // why: this builder runs again when the created account is
            // prepended to the list, and without the flag that second build
            // would queue a second pop.
            if (state.created && !closing) {
              closing = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (dialogContext.mounted) Navigator.of(dialogContext).pop();
              });
            }
            return CreateUserDialog(
              submitting: state.creating,
              errorText: state.createFailure == null
                  ? null
                  : describeUserFailure(state.createFailure!),
              onCreate: (username, password, displayName) => cubit.create(
                username: username,
                password: password,
                displayName: displayName,
              ),
              onCancel: () => Navigator.of(dialogContext).pop(),
            );
          },
        ),
      ),
    );
    cubit.dialogClosed();
  }
}

class _UserRow extends StatelessWidget {
  final UserDto user;

  const _UserRow({required this.user});

  @override
  Widget build(BuildContext context) {
    return AdminResourceRow(
      icon: FluentIcons.contact,
      identifier: user.username,
      title: user.displayName ?? user.username,
      subtitle: 'Создан ${formatDate(user.createdAt)}',
      tags: [
        if (user.isDeleted)
          const AdminStatusTag(label: 'Удалён', tone: AdminStatusTone.neutral)
        else if (user.isBlocked)
          const AdminStatusTag(
            label: 'Заблокирован',
            tone: AdminStatusTone.error,
          )
        else
          const AdminStatusTag(label: 'Активен', tone: AdminStatusTone.success),
        if (user.isPrimaryAdmin)
          const AdminTag(label: 'Основной администратор'),
        if (user.mustChangePassword && !user.isDeleted)
          const AdminStatusTag(
            label: 'Временный пароль',
            tone: AdminStatusTone.warning,
          ),
      ],
      actions: user.isDeleted
          ? const []
          : [
              AdminButton(
                label: 'Изменить',
                size: AdminButtonSize.tonal,
                onPressed: () => _edit(context, user),
              ),
              AdminButton(
                label: user.isBlocked ? 'Разблокировать' : 'Заблокировать',
                size: AdminButtonSize.tonal,
                onPressed: () => _toggleBlocked(context, user),
              ),
              // Deleting the primary administrator is refused server-side
              // unconditionally, so the action is not offered at all — an
              // absent action reads more honestly than one that always fails
              // (`AdminResourceRow`'s own rule).
              if (!user.isPrimaryAdmin)
                AdminButton(
                  label: 'Удалить',
                  size: AdminButtonSize.tonal,
                  onPressed: () => _delete(context, user),
                ),
            ],
    );
  }

  Future<void> _edit(BuildContext context, UserDto user) async {
    final cubit = context.read<UsersCubit>();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => BlocProvider.value(
        value: cubit,
        child: BlocBuilder<UsersCubit, UsersState>(
          builder: (builderContext, state) {
            // The row's own copy of `user` does not update while this dialog
            // is open — it comes from the outer list, which only rebuilds
            // once the dialog closes — so the dialog is seeded from it once
            // and does not need to track later saves itself.
            return EditUserDialog(
              user: user,
              submitting: state.saving,
              errorText: state.actionFailure == null
                  ? null
                  : describeUserFailure(state.actionFailure!),
              roleGranted: state.roleGranted,
              onSaveDisplayName: (value) =>
                  cubit.update(userId: user.id, displayName: value),
              onSetPassword: (password, displayName) => cubit.update(
                userId: user.id,
                displayName: displayName,
                password: password,
              ),
              onGrantRole: (grant) => cubit.grantRole(
                userId: user.id,
                role: grant.role,
                scopeType: grant.scopeType,
                scopeId: grant.scopeId,
              ),
              onClose: () => Navigator.of(dialogContext).pop(),
            );
          },
        ),
      ),
    );
    cubit.clearActionFailure();
  }

  Future<void> _toggleBlocked(BuildContext context, UserDto user) async {
    final cubit = context.read<UsersCubit>();
    if (user.isBlocked) {
      // Reversible and corrective — unblocking only restores what blocking
      // took away, so it does not need the same confirmation blocking does.
      await cubit.setBlocked(user.id, false);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AdminConfirmDialog(
        title: 'Заблокировать «${user.username}»?',
        message:
            'Текущая сессия пользователя завершится немедленно. Вход станет '
            'невозможен до разблокировки.',
        confirmLabel: 'Заблокировать',
        destructive: true,
        onConfirm: () => Navigator.of(dialogContext).pop(true),
        onCancel: () => Navigator.of(dialogContext).pop(false),
      ),
    );
    if (confirmed ?? false) await cubit.setBlocked(user.id, true);
  }

  Future<void> _delete(BuildContext context, UserDto user) async {
    final cubit = context.read<UsersCubit>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AdminConfirmDialog(
        title: 'Удалить «${user.username}»?',
        message:
            'Необратимо: учётная запись перестанет существовать. Отменить '
            'удаление нельзя — при необходимости придётся создать новую '
            'учётную запись.',
        confirmLabel: 'Удалить',
        destructive: true,
        onConfirm: () => Navigator.of(dialogContext).pop(true),
        onCancel: () => Navigator.of(dialogContext).pop(false),
      ),
    );
    if (!(confirmed ?? false)) return;

    await cubit.delete(user.id);
    final failure = cubit.state.actionFailure;
    if (failure == null) return;
    if (!context.mounted) return;
    await _showDeleteRefused(context, failure);
    cubit.clearActionFailure();
  }

  /// `409 sole_group_owner` names the groups a reader has to hand ownership
  /// of before this deletion can succeed — shown as a list, not folded into
  /// one sentence, because the whole point is telling the reader exactly
  /// which groups to act on.
  Future<void> _showDeleteRefused(
    BuildContext context,
    ApiFailure failure,
  ) async {
    final groups = blockingGroupNames(failure);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final colors = AdminColors.of(FluentTheme.of(dialogContext).brightness);
        return ContentDialog(
          constraints: const BoxConstraints(maxWidth: 420),
          title: Text(
            'Не удалось удалить',
            style: AdminTypography.sectionTitle.copyWith(color: colors.text),
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  describeUserFailure(failure),
                  style: AdminTypography.bodySmall.copyWith(
                    color: colors.textSecondary,
                    height: 1.5,
                  ),
                ),
                if (groups.isNotEmpty) ...[
                  const SizedBox(height: AdminSpacing.x12),
                  for (final name in groups)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AdminSpacing.x2,
                      ),
                      child: Text(
                        '· $name',
                        style: AdminTypography.bodySmall.copyWith(
                          color: colors.text,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
          actions: [
            AdminButton(
              label: 'Понятно',
              variant: AdminButtonVariant.accent,
              size: AdminButtonSize.dialog,
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ],
        );
      },
    );
  }
}
