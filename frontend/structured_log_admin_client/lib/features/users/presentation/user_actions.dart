import 'package:fluent_ui/fluent_ui.dart';
import 'package:structured_log_admin_ui/structured_log_admin_ui.dart';

import '../../../shared/api/dto/user_dto.dart';
import 'sole_owner_conflict_dialog.dart';
import 'user_failure_text.dart';
import 'users_cubit.dart';

/// Block/unblock and delete, confirmed and wired the same way from both
/// `UsersPage`'s row (a convenience, matches `Users.dc.html`'s row actions)
/// and `UserDetailPage`'s header (the primary place for them now) — one
/// place for the confirmation copy and the `sole_group_owner` handling
/// rather than two copies that would drift.
Future<void> toggleUserBlocked(
  BuildContext context,
  UsersCubit cubit,
  UserDto user,
) async {
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

/// [onDeleted] runs only once the account is actually gone — `UsersPage`'s
/// row has nothing to do (the list drops it on its own), `UserDetailPage`
/// navigates back to the list, since there is nothing left here to show.
Future<void> deleteUser(
  BuildContext context,
  UsersCubit cubit,
  UserDto user, {
  VoidCallback? onDeleted,
}) async {
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
  if (failure == null) {
    onDeleted?.call();
    return;
  }
  if (!context.mounted) return;

  final groups = blockingGroups(failure);
  // Some other refusal — the page's own banner explains it.
  if (groups.isEmpty) return;

  cubit.clearActionFailure();
  if (!context.mounted) return;
  await _showSoleOwnerConflict(context, cubit, groups);
}

/// `409 sole_group_owner` names the groups this deletion is blocked by, each
/// with a way to hand ownership onward right there (`SoleOwnerConflictDialog`
/// mirrors the mockup's own artboard for this case, replacing an earlier
/// unnamed inline dialog that only listed the names).
Future<void> _showSoleOwnerConflict(
  BuildContext context,
  UsersCubit cubit,
  List<({int id, String name})> groups,
) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => SoleOwnerConflictDialog(
      groups: groups,
      onGrantAccess: (group) async {
        Navigator.of(dialogContext).pop();
        if (!context.mounted) return;
        await showGrantAccessToGroup(
          context,
          groupId: group.id,
          groupName: group.name,
          searchUsers: cubit.searchUsers,
          searchTeams: (query) => cubit.searchTeamsOfGroup(group.id, query),
          onGrant:
              ({
                required subjectType,
                required subjectId,
                required role,
              }) async {
                await cubit.grantAccessToGroup(
                  groupId: group.id,
                  subjectType: subjectType,
                  subjectId: subjectId,
                  role: role,
                );
              },
        );
      },
      onClose: () => Navigator.of(dialogContext).pop(),
    ),
  );
}
