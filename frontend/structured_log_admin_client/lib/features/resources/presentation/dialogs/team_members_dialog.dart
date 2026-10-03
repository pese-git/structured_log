import 'package:fluent_ui/fluent_ui.dart';
import 'package:structured_log_admin_ui/structured_log_admin_ui.dart';
import '../../../../l10n/l10n.dart';
import '../../../../shared/api/cursor_page.dart';
import '../../../../shared/api/dto/resource_dto.dart';
import '../../../../shared/api/dto/user_dto.dart';

/// A team's current members, plus a picker to add one more (`13.2a`).
///
/// Stays open across an add/remove — unlike `GrantAccessDialog`, which
/// closes on success, this is a management surface a reader works through
/// one member at a time, the same reasoning `EditUserDialog`'s own
/// role-grant section follows. [members]/[loading]/[changing]/[errorText]
/// come from the cubit's state for the team currently open, so the caller
/// wraps this in the same `BlocBuilder` pattern as `_Access` above.
class TeamMembersDialog extends StatefulWidget {
  final String teamName;
  final String groupName;
  final List<TeamMemberDto> members;
  final bool loading;
  final bool changing;
  final String? errorText;
  final Future<CursorPage<UserDto>> Function(String query) searchUsers;
  final ValueChanged<int> onAdd;
  final ValueChanged<int> onRemove;
  final VoidCallback onClose;

  const TeamMembersDialog({
    super.key,
    required this.teamName,
    required this.groupName,
    required this.members,
    required this.searchUsers,
    required this.onAdd,
    required this.onRemove,
    required this.onClose,
    this.loading = false,
    this.changing = false,
    this.errorText,
  });

  @override
  State<TeamMembersDialog> createState() => _TeamMembersDialogState();
}

class _TeamMembersDialogState extends State<TeamMembersDialog> {
  int? _candidateId;

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);
    final memberIds = widget.members.map((m) => m.userId).toSet();

    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 480),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.resTeamMembersTitle(widget.teamName),
            style: AdminTypography.sectionTitle.copyWith(color: colors.text),
          ),
          const SizedBox(height: AdminSpacing.x4),
          Text(
            context.l10n.resGroupPrefix(widget.groupName),
            style: AdminTypography.bodySmall.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
      // Scrolling, like the quota dialogs above — same reasoning
      // (`test/features/resources/dialog_layout_test.dart`).
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.errorText != null) ...[
              AdminBanner(
                message: widget.errorText!,
                tone: AdminBannerTone.error,
              ),
              const SizedBox(height: AdminSpacing.x14),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  // Remounted whenever the member list changes — after a
                  // successful add there is no other way to clear the
                  // picker's own text/selection back to empty, since it
                  // exposes neither. Keyed by a string, not the sorted `List`:
                  // a `List` compares by identity, so it remounted the picker
                  // on every rebuild — including the one each keystroke
                  // triggers through `onSelected(null)`, which emptied the
                  // field after the first character.
                  child: AdminSearchPicker<int>(
                    key: ValueKey((memberIds.toList()..sort()).join(',')),
                    label: context.l10n.resAddMember,
                    placeholder: context.l10n.resSearchUserHint,
                    enabled: !widget.changing,
                    onSearch: (query) async {
                      final truncated = context.l10n.commonSearchTruncated;
                      final users = await widget.searchUsers(query);
                      return [
                        for (final u in users.items)
                          if (!memberIds.contains(u.id))
                            AdminSearchPickerItem(
                              value: u.id,
                              label: u.username,
                            ),
                        if (users.hasMore)
                          AdminSearchPickerItem.hint(truncated),
                      ];
                    },
                    onSelected: (item) =>
                        setState(() => _candidateId = item?.value),
                  ),
                ),
                const SizedBox(width: AdminSpacing.x10),
                AdminButton(
                  label: context.l10n.resAdd,
                  size: AdminButtonSize.dialog,
                  onPressed: widget.changing || _candidateId == null
                      ? null
                      : () {
                          final id = _candidateId!;
                          setState(() => _candidateId = null);
                          widget.onAdd(id);
                        },
                ),
              ],
            ),
            const SizedBox(height: AdminSpacing.x14),
            if (widget.loading)
              const Center(child: AdminLoadingIndicator())
            else if (widget.members.isEmpty)
              AdminEmptyState(
                icon: FluentIcons.contact,
                title: context.l10n.resNoMembers,
                description: context.l10n.resNoMembersHint,
              )
            else
              for (final member in widget.members) ...[
                AdminResourceRow(
                  icon: FluentIcons.contact,
                  title: member.username,
                  actions: [
                    AdminButton(
                      label: context.l10n.resDelete,
                      size: AdminButtonSize.tonal,
                      onPressed: widget.changing
                          ? null
                          : () => widget.onRemove(member.userId),
                    ),
                  ],
                ),
                const SizedBox(height: AdminSpacing.x10),
              ],
          ],
        ),
      ),
      actions: [
        AdminButton(
          label: context.l10n.resClose,
          variant: AdminButtonVariant.accent,
          size: AdminButtonSize.dialog,
          onPressed: widget.onClose,
        ),
      ],
    );
  }
}
