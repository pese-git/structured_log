import 'package:fluent_ui/fluent_ui.dart';
import 'package:structured_log_admin_ui/structured_log_admin_ui.dart';
import '../../../../l10n/l10n.dart';
import '../../../../shared/api/cursor_page.dart';
import '../../../../shared/api/dto/resource_dto.dart';
import '../../../../shared/api/dto/user_dto.dart';

/// A «Доступ» row's title — the resolved name the server sends, or a
/// fallback naming the subject's kind, so a team grant never reads as a
/// user's (13.5, full version: the subject can now be either).
String subjectLabel(AppLocalizations l10n, RoleAssignmentDto grant) {
  if (grant.subjectName != null) return grant.subjectName!;
  return grant.subjectType == 'team'
      ? l10n.resSubjectTeam(grant.subjectId)
      : l10n.resSubjectUser(grant.subjectId);
}

/// What a group/project «Доступ» section's grant dialog produced.
typedef AccessGrantValues = ({String subjectType, int subjectId, String role});

/// Grants a role on a fixed group/project to a user or a team picked by name
/// — the mirror image of `EditUserDialog`'s role-grant section, which fixes
/// the user and lets the admin pick the scope (уточнение 17.09.2026). `role`
/// defaults to `owner`/`user` — the only roles an `owner` may grant
/// (`_GroupRolePicker`) — and widens to include `admin` when [isGlobalAdmin]
/// says the caller's token claims it (13.5, full version): a client-side
/// hint only, never the source of truth — the server re-derives the
/// caller's actual rights on every request regardless of what this form
/// offered (`specs/admin-client-resource-management`, requirement «Выдача и
/// отзыв ролей пользователю или команде»).
class GrantAccessDialog extends StatefulWidget {
  final String scopeLabel;
  final bool submitting;
  final bool isGlobalAdmin;
  final String? errorText;
  final Future<CursorPage<UserDto>> Function(String query) searchUsers;

  /// Candidates for the team-recipient mode — already narrowed to teams of
  /// the group this grant is on (or that group's project is in), the same
  /// scope the server's own owner-delegation rule requires of a team
  /// recipient.
  final Future<List<TeamDto>> Function(String query) searchTeams;
  final ValueChanged<AccessGrantValues> onGrant;
  final VoidCallback onCancel;

  const GrantAccessDialog({
    super.key,
    required this.scopeLabel,
    required this.searchUsers,
    required this.searchTeams,
    required this.onGrant,
    required this.onCancel,
    this.submitting = false,
    this.isGlobalAdmin = false,
    this.errorText,
  });

  @override
  State<GrantAccessDialog> createState() => _GrantAccessDialogState();
}

class _GrantAccessDialogState extends State<GrantAccessDialog> {
  String _role = 'user';
  String _subjectType = 'user';
  int? _subjectId;

  void _submit() {
    final subjectId = _subjectId;
    if (subjectId == null) return;
    widget.onGrant((
      subjectType: _subjectType,
      subjectId: subjectId,
      role: _role,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);
    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 440),
      title: Text(
        context.l10n.resGrantAccess,
        style: AdminTypography.sectionTitle.copyWith(color: colors.text),
      ),
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
            Text(
              widget.scopeLabel,
              style: AdminTypography.bodySmall.copyWith(
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: AdminSpacing.x14),
            _SubjectTypePicker(
              value: _subjectType,
              onChanged: (value) => setState(() {
                _subjectType = value;
                // The old pick is the wrong kind of subject for the picker
                // that is about to replace it — keeping it would grant a
                // role to whoever the field no longer shows (same reasoning
                // as `EditUserDialog`'s `_ScopeTypePicker`).
                _subjectId = null;
              }),
            ),
            const SizedBox(height: AdminSpacing.x14),
            // Keyed on subject type so switching user ↔ team mounts a fresh
            // picker instead of reusing one still holding the other kind's
            // text and results. Labelled generically, not 'Пользователь'/
            // 'Команда' — the picker right above it already says which one
            // this is; repeating it here only duplicated that text on
            // screen (13.5, found by the browser-driven e2e test expecting
            // one 'Пользователь', not two).
            AdminSearchPicker<int>(
              key: ValueKey(_subjectType),
              label: context.l10n.resRecipientName,
              placeholder: _subjectType == 'user'
                  ? context.l10n.resSearchUserHint
                  : context.l10n.resSearchTeamHint,
              onSearch: (query) async {
                // Read before the awaits: the context may be gone by then.
                final truncated = context.l10n.commonSearchTruncated;
                if (_subjectType == 'team') {
                  final teams = await widget.searchTeams(query);
                  return [
                    for (final t in teams)
                      AdminSearchPickerItem(value: t.id, label: t.name),
                  ];
                }
                final users = await widget.searchUsers(query);
                return [
                  for (final u in users.items)
                    AdminSearchPickerItem(value: u.id, label: u.username),
                  if (users.hasMore) AdminSearchPickerItem.hint(truncated),
                ];
              },
              onSelected: (item) => setState(() => _subjectId = item?.value),
            ),
            const SizedBox(height: AdminSpacing.x14),
            _GroupRolePicker(
              value: _role,
              includeAdmin: widget.isGlobalAdmin,
              onChanged: (value) => setState(() => _role = value),
            ),
          ],
        ),
      ),
      actions: [
        AdminButton(
          label: context.l10n.resCancel,
          size: AdminButtonSize.dialog,
          onPressed: widget.submitting ? null : widget.onCancel,
        ),
        AdminButton(
          label: context.l10n.resGrant,
          variant: AdminButtonVariant.accent,
          size: AdminButtonSize.dialog,
          onPressed: widget.submitting ? null : _submit,
        ),
      ],
    );
  }
}

class _SubjectTypePicker extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _SubjectTypePicker({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.resRecipient,
          style: AdminTypography.label.copyWith(color: colors.text),
        ),
        const SizedBox(height: AdminSpacing.x6),
        ComboBox<String>(
          value: value,
          isExpanded: true,
          items: [
            ComboBoxItem(value: 'user', child: Text(context.l10n.resUser)),
            ComboBoxItem(value: 'team', child: Text(context.l10n.resTeam)),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ],
    );
  }
}

/// `owner`/`user` always — the only roles an `owner` may grant on a group or
/// project — plus `admin` when [includeAdmin] says the caller's own token
/// claims global `admin` (13.5, full version): `admin` is otherwise a global
/// role, not one to hold "on" a group or project, so it stays off this list
/// for anyone the form does not already know is unrestricted.
class _GroupRolePicker extends StatelessWidget {
  final String value;
  final bool includeAdmin;
  final ValueChanged<String> onChanged;

  const _GroupRolePicker({
    required this.value,
    required this.onChanged,
    this.includeAdmin = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.resRole,
          style: AdminTypography.label.copyWith(color: colors.text),
        ),
        const SizedBox(height: AdminSpacing.x6),
        ComboBox<String>(
          value: value,
          isExpanded: true,
          items: [
            if (includeAdmin)
              const ComboBoxItem(value: 'admin', child: Text('admin')),
            const ComboBoxItem(value: 'owner', child: Text('owner')),
            const ComboBoxItem(value: 'user', child: Text('user')),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ],
    );
  }
}
