import 'package:fluent_ui/fluent_ui.dart';
import 'package:structured_log_admin_ui/structured_log_admin_ui.dart';

import '../../../shared/api/dto/resource_dto.dart';
import '../../../shared/api/dto/user_dto.dart';

/// `Новый пользователь` — username, a temporary password, and an optional
/// display name. No `email` field: this stage's server does not accept one
/// (`CreateUserRequestDto`).
class CreateUserDialog extends StatefulWidget {
  final bool submitting;
  final String? errorText;
  final void Function(String username, String password, String? displayName)
  onCreate;
  final VoidCallback onCancel;

  const CreateUserDialog({
    super.key,
    required this.onCreate,
    required this.onCancel,
    this.submitting = false,
    this.errorText,
  });

  @override
  State<CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends State<CreateUserDialog> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _displayName = TextEditingController();

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _displayName.dispose();
    super.dispose();
  }

  void _submit() {
    final username = _username.text.trim();
    final password = _password.text;
    if (username.isEmpty || password.isEmpty) return;
    final displayName = _displayName.text.trim();
    widget.onCreate(
      username,
      password,
      displayName.isEmpty ? null : displayName,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);
    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 440),
      title: Text(
        'Новый пользователь',
        style: AdminTypography.sectionTitle.copyWith(color: colors.text),
      ),
      // Scrolling for the reason every dialog in this app scrolls: a bare
      // `Column` inside `ContentDialog`'s loose `Flexible` takes the whole of
      // it (`resource_dialogs.dart`).
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
            AdminTextField(
              label: 'Имя пользователя',
              controller: _username,
              autofocus: true,
            ),
            const SizedBox(height: AdminSpacing.x14),
            AdminTextField(
              label: 'Временный пароль',
              controller: _password,
              obscure: true,
            ),
            const SizedBox(height: AdminSpacing.x14),
            AdminTextField(
              label: 'Отображаемое имя (необязательно)',
              controller: _displayName,
            ),
            const SizedBox(height: AdminSpacing.x10),
            Text(
              'Пользователю нужно будет сменить этот пароль при первом входе.',
              style: AdminTypography.caption.copyWith(
                color: colors.textSecondary,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
      actions: [
        AdminButton(
          label: 'Отмена',
          size: AdminButtonSize.dialog,
          onPressed: widget.submitting ? null : widget.onCancel,
        ),
        AdminButton(
          label: 'Создать пользователя',
          variant: AdminButtonVariant.accent,
          size: AdminButtonSize.dialog,
          onPressed: widget.submitting ? null : _submit,
        ),
      ],
    );
  }
}

/// What an [EditUserDialog]'s role-grant section produced.
typedef RoleGrantValues = ({String role, String scopeType, int? scopeId});

/// `Изменить пользователя` — profile fields, the subject's current grants,
/// and the reduced role-grant form (13.5a) underneath: the subject is fixed
/// to this user, and the admin picks role/scope. The mirror image lives on
/// the group/project side (`GrantAccessDialog`, уточнение 17.09.2026): fixes
/// the scope, lets the admin pick the subject.
class EditUserDialog extends StatefulWidget {
  final UserDto user;
  final bool submitting;
  final String? errorText;

  /// This user's current grants, any scope — loaded when the dialog opens.
  final List<RoleAssignmentDto> roleAssignments;
  final ValueChanged<String?> onSaveDisplayName;

  /// The password, and the display name to resend alongside it — the
  /// server's `PATCH` always needs a value for `display_name` from this
  /// dialog (`UpdateUserRequestDto`), and it has to be the one currently in
  /// the field, not [user]'s: that copy is a snapshot from when the dialog
  /// opened and does not track an earlier `onSaveDisplayName` in the same
  /// session, which would otherwise be silently undone by this call.
  final void Function(String password, String? displayName) onSetPassword;
  final ValueChanged<RoleGrantValues> onGrantRole;

  /// Revokes one of [roleAssignments] by its id.
  final ValueChanged<int> onRevokeRole;
  final VoidCallback onClose;

  /// Resolve the "Область" picker's results by name — never by an id the
  /// admin is expected to know (`AdminSearchPicker`, `RoleAssignment.dc.html`).
  final Future<List<GroupDto>> Function(String query) searchGroups;
  final Future<List<ProjectDto>> Function(String query) searchProjects;

  const EditUserDialog({
    super.key,
    required this.user,
    required this.onSaveDisplayName,
    required this.onSetPassword,
    required this.onGrantRole,
    required this.onRevokeRole,
    required this.onClose,
    required this.searchGroups,
    required this.searchProjects,
    this.submitting = false,
    this.errorText,
    this.roleAssignments = const [],
  });

  @override
  State<EditUserDialog> createState() => _EditUserDialogState();
}

class _EditUserDialogState extends State<EditUserDialog> {
  late final _displayName = TextEditingController(
    text: widget.user.displayName ?? '',
  );
  final _newPassword = TextEditingController();

  var _role = 'user';
  var _scopeType = 'global';

  /// The picked group/project — `null` for `global` (no scope to pick) and
  /// also `null` whenever the picker's text no longer matches a selection
  /// (`AdminSearchPicker.onSelected`, cleared as soon as the reader edits
  /// what it shows).
  int? _scopeId;

  @override
  void dispose() {
    _displayName.dispose();
    _newPassword.dispose();
    super.dispose();
  }

  void _saveProfile() {
    final value = _displayName.text.trim();
    widget.onSaveDisplayName(value.isEmpty ? null : value);
  }

  void _setPassword() {
    final value = _newPassword.text;
    if (value.isEmpty) return;
    final displayName = _displayName.text.trim();
    widget.onSetPassword(value, displayName.isEmpty ? null : displayName);
  }

  void _grantRole() {
    if (_scopeType != 'global' && _scopeId == null) return;
    widget.onGrantRole((role: _role, scopeType: _scopeType, scopeId: _scopeId));
  }

  Future<void> _revokeRole(
    BuildContext context,
    RoleAssignmentDto grant,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AdminConfirmDialog(
        title: 'Отозвать роль «${grant.role}»?',
        message: 'Доступ (${_scopeLabel(grant)}) будет отозван немедленно.',
        confirmLabel: 'Отозвать',
        destructive: true,
        onConfirm: () => Navigator.of(dialogContext).pop(true),
        onCancel: () => Navigator.of(dialogContext).pop(false),
      ),
    );
    if (confirmed ?? false) widget.onRevokeRole(grant.id);
  }

  static String _scopeLabel(RoleAssignmentDto grant) {
    return switch (grant.scopeType) {
      'global' => 'вся система',
      'group' => 'группа: ${grant.scopeName ?? '#${grant.scopeId}'}',
      'project' => 'проект: ${grant.scopeName ?? '#${grant.scopeId}'}',
      _ => grant.scopeType,
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);
    final user = widget.user;

    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 480),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Изменить пользователя',
            style: AdminTypography.sectionTitle.copyWith(color: colors.text),
          ),
          const SizedBox(height: AdminSpacing.x4),
          Text(
            user.username,
            style: AdminTypography.bodySmall.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
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
              'Профиль',
              style: AdminTypography.label.copyWith(color: colors.text),
            ),
            const SizedBox(height: AdminSpacing.x10),
            AdminTextField(label: 'Отображаемое имя', controller: _displayName),
            const SizedBox(height: AdminSpacing.x10),
            Align(
              alignment: Alignment.centerRight,
              child: AdminButton(
                label: 'Сохранить имя',
                size: AdminButtonSize.tonal,
                onPressed: widget.submitting ? null : _saveProfile,
              ),
            ),
            const SizedBox(height: AdminSpacing.x18),
            Text(
              'Новый пароль',
              style: AdminTypography.label.copyWith(color: colors.text),
            ),
            const SizedBox(height: AdminSpacing.x6),
            Text(
              'Немедленно завершит текущую сессию пользователя — при '
              'следующем входе потребуется сменить этот пароль на свой.',
              style: AdminTypography.caption.copyWith(
                color: colors.textSecondary,
                height: 1.45,
              ),
            ),
            const SizedBox(height: AdminSpacing.x10),
            AdminTextField(
              label: 'Пароль',
              controller: _newPassword,
              obscure: true,
              placeholder: 'Не менять',
            ),
            const SizedBox(height: AdminSpacing.x10),
            Align(
              alignment: Alignment.centerRight,
              child: AdminButton(
                label: 'Установить пароль',
                size: AdminButtonSize.tonal,
                onPressed: widget.submitting ? null : _setPassword,
              ),
            ),
            const SizedBox(height: AdminSpacing.x18),
            Text(
              'Права доступа',
              style: AdminTypography.label.copyWith(color: colors.text),
            ),
            const SizedBox(height: AdminSpacing.x6),
            Text(
              'Только для этого пользователя. Область — вся система, группа '
              'или проект.',
              style: AdminTypography.caption.copyWith(
                color: colors.textSecondary,
                height: 1.45,
              ),
            ),
            const SizedBox(height: AdminSpacing.x10),
            if (widget.roleAssignments.isEmpty)
              Text(
                'Ролей пока не выдано.',
                style: AdminTypography.bodySmall.copyWith(
                  color: colors.textSecondary,
                ),
              )
            else
              for (final grant in widget.roleAssignments) ...[
                AdminResourceRow(
                  icon: FluentIcons.permissions,
                  title: grant.role,
                  subtitle: _scopeLabel(grant),
                  actions: [
                    AdminButton(
                      label: 'Отозвать',
                      size: AdminButtonSize.tonal,
                      onPressed: () => _revokeRole(context, grant),
                    ),
                  ],
                ),
                const SizedBox(height: AdminSpacing.x10),
              ],
            const SizedBox(height: AdminSpacing.x10),
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
                      // The old pick names a group/project of the wrong
                      // kind (or, from `global`, no scope at all) — keeping
                      // it would grant a role over a scope the field no
                      // longer shows.
                      _scopeId = null;
                    }),
                  ),
                ),
              ],
            ),
            if (_scopeType != 'global') ...[
              const SizedBox(height: AdminSpacing.x10),
              // Keyed on scope type so switching group ↔ project mounts a
              // fresh picker instead of reusing one still holding the other
              // kind's text and results.
              AdminSearchPicker<int>(
                key: ValueKey(_scopeType),
                label: _scopeType == 'group' ? 'Группа' : 'Проект',
                placeholder: 'Начните вводить название…',
                onSearch: (query) async {
                  if (_scopeType == 'group') {
                    final items = await widget.searchGroups(query);
                    return [
                      for (final g in items)
                        AdminSearchPickerItem(value: g.id, label: g.name),
                    ];
                  }
                  final items = await widget.searchProjects(query);
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
                onPressed: widget.submitting ? null : _grantRole,
              ),
            ),
          ],
        ),
      ),
      actions: [
        AdminButton(
          label: 'Закрыть',
          variant: AdminButtonVariant.accent,
          size: AdminButtonSize.dialog,
          onPressed: widget.onClose,
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
