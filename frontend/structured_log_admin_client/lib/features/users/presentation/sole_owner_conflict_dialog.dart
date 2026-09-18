import 'package:fluent_ui/fluent_ui.dart';
import 'package:structured_log_admin_ui/structured_log_admin_ui.dart';

import '../../../shared/api/dto/resource_dto.dart';
import '../../../shared/api/dto/user_dto.dart';
import '../../resources/presentation/resource_dialogs.dart'
    show GrantAccessDialog;

/// `409 sole_group_owner` on a user delete — the groups it named as blocked,
/// each with a way to hand ownership onward right there
/// (`SoleOwnerConflictDialog.dc.html`).
///
/// Replaces `UsersPage`'s previous ad hoc, unnamed `ContentDialog` for this
/// case: the mockup draws it as its own artboard, with a per-group action the
/// old inline version did not have.
///
/// Tapping «Выдать роль» closes this dialog and opens `GrantAccessDialog`
/// scoped to that one group, rather than stacking a second dialog on top —
/// simpler, and the reader's goal (transfer ownership) is a single action
/// they can immediately retry the delete after, not a flow that needs this
/// dialog to still be there when it is done.
class SoleOwnerConflictDialog extends StatelessWidget {
  final List<({int id, String name})> groups;
  final void Function(({int id, String name}) group) onGrantAccess;
  final VoidCallback onClose;

  const SoleOwnerConflictDialog({
    super.key,
    required this.groups,
    required this.onGrantAccess,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);

    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 480),
      title: Text(
        'Сначала передайте владение',
        style: AdminTypography.sectionTitle.copyWith(color: colors.text),
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Пользователь — единственный владелец (owner) следующих групп. '
              'Выдайте роль владельца ещё кому-то в каждой из них, прежде '
              'чем удаление станет возможным.',
              style: AdminTypography.bodySmall.copyWith(
                color: colors.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: AdminSpacing.x12),
            // Not `AdminResourceRow`: its title/tags/actions sit in one
            // unwrapped `Row`, and a long tag plus "Выдать роль" together
            // overflow this dialog's 480px width. The mockup keeps the
            // button clear of the name+tag by putting it at the row's far
            // end regardless of their width — `Expanded` does the same here.
            for (final group in groups) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AdminSpacing.x12,
                  vertical: AdminSpacing.x10,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: colors.border),
                  borderRadius: BorderRadius.circular(AdminRadius.control),
                ),
                child: Row(
                  children: [
                    Icon(
                      FluentIcons.group,
                      size: 15,
                      color: colors.textSecondary,
                    ),
                    const SizedBox(width: AdminSpacing.x8),
                    Expanded(
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: AdminSpacing.x8,
                        runSpacing: AdminSpacing.x4,
                        children: [
                          Text(
                            group.name,
                            overflow: TextOverflow.ellipsis,
                            style: AdminTypography.body.copyWith(
                              color: colors.text,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const AdminTag(label: 'единственный owner'),
                        ],
                      ),
                    ),
                    const SizedBox(width: AdminSpacing.x8),
                    AdminButton(
                      label: 'Выдать роль',
                      size: AdminButtonSize.tonal,
                      onPressed: () => onGrantAccess(group),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AdminSpacing.x10),
            ],
          ],
        ),
      ),
      actions: [
        AdminButton(
          label: 'Понятно',
          variant: AdminButtonVariant.accent,
          size: AdminButtonSize.dialog,
          onPressed: onClose,
        ),
      ],
    );
  }
}

/// Opens [GrantAccessDialog] scoped to [group], wired against [cubit]'s
/// generic role-assignment access (not tied to any one subject the way
/// `UserDetailPage`'s own role card is) — the reusable half of
/// `SoleOwnerConflictDialog`'s «Выдать роль», kept a free function rather
/// than a method on the dialog itself because it needs a `BuildContext` of
/// its own once the dialog that opened it has already closed.
Future<void> showGrantAccessToGroup(
  BuildContext context, {
  required int groupId,
  required String groupName,
  required Future<List<UserDto>> Function(String query) searchUsers,
  required Future<List<TeamDto>> Function(String query) searchTeams,
  required Future<void> Function({
    required String subjectType,
    required int subjectId,
    required String role,
  })
  onGrant,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => GrantAccessDialog(
      scopeLabel: 'группа: $groupName',
      // Reachable only from the Users screen, which the shell already
      // offers admin-only — same reasoning `EditUserPage`'s role card uses.
      isGlobalAdmin: true,
      searchUsers: searchUsers,
      searchTeams: searchTeams,
      onGrant: (values) async {
        await onGrant(
          subjectType: values.subjectType,
          subjectId: values.subjectId,
          role: values.role,
        );
        if (dialogContext.mounted) Navigator.of(dialogContext).pop();
      },
      onCancel: () => Navigator.of(dialogContext).pop(),
    ),
  );
}
