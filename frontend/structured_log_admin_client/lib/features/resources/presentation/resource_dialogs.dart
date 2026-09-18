import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:structured_log_admin_ui/structured_log_admin_ui.dart';

import '../../../shared/api/dto/resource_dto.dart';
import '../../../shared/api/dto/user_dto.dart';

/// What a quota form produced. `null` in a limit means unlimited, and it is
/// sent as `null` rather than left out (`UpdateProjectQuotaRequestDto`).
typedef QuotaValues = ({int retentionDays, int? maxEntries, int? maxBytes});

/// A «Доступ» row's title — the resolved name the server sends, or a
/// fallback naming the subject's kind, so a team grant never reads as a
/// user's (13.5, full version: the subject can now be either).
String subjectLabel(RoleAssignmentDto grant) {
  if (grant.subjectName != null) return grant.subjectName!;
  return grant.subjectType == 'team'
      ? 'Команда #${grant.subjectId}'
      : 'Пользователь #${grant.subjectId}';
}

/// A field and the "без лимита" checkbox beside it, as the quota dialogs draw
/// it. Checking the box is what "no limit" means, and it empties the field
/// rather than leaving a number nobody will honour.
class _LimitField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool unlimited;
  final ValueChanged<bool> onUnlimitedChanged;

  const _LimitField({
    required this.label,
    required this.controller,
    required this.unlimited,
    required this.onUnlimitedChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: AdminTextField(
            label: label,
            controller: controller,
            enabled: !unlimited,
            placeholder: unlimited ? '—' : null,
          ),
        ),
        const SizedBox(width: AdminSpacing.x10),
        Padding(
          padding: const EdgeInsets.only(bottom: AdminSpacing.x6),
          child: Checkbox(
            checked: unlimited,
            onChanged: (value) => onUnlimitedChanged(value ?? false),
            content: Text(
              'без лимита',
              style: AdminTypography.bodySmall.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Everything the quota dialogs share: three numbers, two of which may be
/// absent.
class _QuotaFields extends StatelessWidget {
  final TextEditingController retention;
  final TextEditingController entries;
  final TextEditingController bytes;
  final bool entriesUnlimited;
  final bool bytesUnlimited;
  final ValueChanged<bool> onEntriesUnlimited;
  final ValueChanged<bool> onBytesUnlimited;

  const _QuotaFields({
    required this.retention,
    required this.entries,
    required this.bytes,
    required this.entriesUnlimited,
    required this.bytesUnlimited,
    required this.onEntriesUnlimited,
    required this.onBytesUnlimited,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminTextField(
          label: 'Срок хранения, дней (retention_days)',
          controller: retention,
        ),
        const SizedBox(height: AdminSpacing.x14),
        _LimitField(
          label: 'Лимит записей (max_entries)',
          controller: entries,
          unlimited: entriesUnlimited,
          onUnlimitedChanged: onEntriesUnlimited,
        ),
        const SizedBox(height: AdminSpacing.x14),
        _LimitField(
          label: 'Лимит объёма, МБ (max_bytes)',
          controller: bytes,
          unlimited: bytesUnlimited,
          onUnlimitedChanged: onBytesUnlimited,
        ),
      ],
    );
  }
}

/// Megabytes on screen, bytes on the wire. The artboard labels the field
/// "МБ" and the API counts bytes; converting in one place keeps the two from
/// disagreeing by a factor of a million.
const _bytesPerMegabyte = 1024 * 1024;

int? _parseLimit(String text, bool unlimited, {int scale = 1}) {
  if (unlimited) return null;
  final value = int.tryParse(text.trim());
  return value == null ? null : value * scale;
}

/// `Новый проект` (`CreateProjectDialog.dc.html`).
class CreateProjectDialog extends StatefulWidget {
  final String groupName;
  final bool submitting;
  final String? errorText;
  final void Function(String name, QuotaValues quota) onCreate;
  final VoidCallback onCancel;

  const CreateProjectDialog({
    super.key,
    required this.groupName,
    required this.onCreate,
    required this.onCancel,
    this.submitting = false,
    this.errorText,
  });

  @override
  State<CreateProjectDialog> createState() => _CreateProjectDialogState();
}

class _CreateProjectDialogState extends State<CreateProjectDialog> {
  final _name = TextEditingController();
  final _retention = TextEditingController(text: '30');
  final _entries = TextEditingController();
  final _bytes = TextEditingController();
  var _entriesUnlimited = true;
  var _bytesUnlimited = true;

  @override
  void dispose() {
    _name.dispose();
    _retention.dispose();
    _entries.dispose();
    _bytes.dispose();
    super.dispose();
  }

  void _submit() {
    widget.onCreate(_name.text.trim(), (
      retentionDays: int.tryParse(_retention.text.trim()) ?? 30,
      maxEntries: _parseLimit(_entries.text, _entriesUnlimited),
      maxBytes: _parseLimit(
        _bytes.text,
        _bytesUnlimited,
        scale: _bytesPerMegabyte,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);
    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 480),
      title: Text(
        'Новый проект',
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
              'Группа',
              style: AdminTypography.bodySmall.copyWith(color: colors.text),
            ),
            const SizedBox(height: AdminSpacing.x6),
            AdminTag(label: widget.groupName),
            const SizedBox(height: AdminSpacing.x14),
            AdminTextField(
              label: 'Название проекта',
              controller: _name,
              autofocus: true,
            ),
            const SizedBox(height: AdminSpacing.x14),
            _QuotaFields(
              retention: _retention,
              entries: _entries,
              bytes: _bytes,
              entriesUnlimited: _entriesUnlimited,
              bytesUnlimited: _bytesUnlimited,
              onEntriesUnlimited: (v) => setState(() => _entriesUnlimited = v),
              onBytesUnlimited: (v) => setState(() => _bytesUnlimited = v),
            ),
            const SizedBox(height: AdminSpacing.x14),
            Text(
              'Секретный ключ для приёма логов создаётся отдельно, на экране '
              'проекта, после его создания.',
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
          label: 'Создать проект',
          variant: AdminButtonVariant.accent,
          size: AdminButtonSize.dialog,
          onPressed: widget.submitting ? null : _submit,
        ),
      ],
    );
  }
}

/// `Изменить квоту` (`EditQuotaDialog.dc.html`).
class EditQuotaDialog extends StatefulWidget {
  final String projectName;
  final int retentionDays;
  final int? maxEntries;
  final int? maxBytes;
  final bool submitting;
  final String? errorText;
  final ValueChanged<QuotaValues> onSave;
  final VoidCallback onCancel;

  const EditQuotaDialog({
    super.key,
    required this.projectName,
    required this.retentionDays,
    required this.maxEntries,
    required this.maxBytes,
    required this.onSave,
    required this.onCancel,
    this.submitting = false,
    this.errorText,
  });

  @override
  State<EditQuotaDialog> createState() => _EditQuotaDialogState();
}

class _EditQuotaDialogState extends State<EditQuotaDialog> {
  late final _retention = TextEditingController(
    text: '${widget.retentionDays}',
  );
  late final _entries = TextEditingController(
    text: widget.maxEntries?.toString() ?? '',
  );
  late final _bytes = TextEditingController(
    text: widget.maxBytes == null
        ? ''
        : '${widget.maxBytes! ~/ _bytesPerMegabyte}',
  );
  late var _entriesUnlimited = widget.maxEntries == null;
  late var _bytesUnlimited = widget.maxBytes == null;

  @override
  void dispose() {
    _retention.dispose();
    _entries.dispose();
    _bytes.dispose();
    super.dispose();
  }

  void _submit() {
    widget.onSave((
      retentionDays:
          int.tryParse(_retention.text.trim()) ?? widget.retentionDays,
      maxEntries: _parseLimit(_entries.text, _entriesUnlimited),
      maxBytes: _parseLimit(
        _bytes.text,
        _bytesUnlimited,
        scale: _bytesPerMegabyte,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);
    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 440),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Изменить квоту',
            style: AdminTypography.sectionTitle.copyWith(color: colors.text),
          ),
          const SizedBox(height: AdminSpacing.x4),
          Text(
            'Проект: ${widget.projectName}',
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
            _QuotaFields(
              retention: _retention,
              entries: _entries,
              bytes: _bytes,
              entriesUnlimited: _entriesUnlimited,
              bytesUnlimited: _bytesUnlimited,
              onEntriesUnlimited: (v) => setState(() => _entriesUnlimited = v),
              onBytesUnlimited: (v) => setState(() => _bytesUnlimited = v),
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
          label: 'Сохранить',
          variant: AdminButtonVariant.accent,
          size: AdminButtonSize.dialog,
          onPressed: widget.submitting ? null : _submit,
        ),
      ],
    );
  }
}

/// `Ключ создан` (`SecretKeyReveal.dc.html`).
///
/// The only place the value of a secret key is ever on screen. There is no
/// second chance: the server keeps a hash, and closing this dialog is the
/// moment the value stops existing
/// (`specs/admin-client-resource-management`).
class SecretKeyRevealDialog extends StatelessWidget {
  final String projectName;
  final String label;
  final String secret;
  final VoidCallback onClose;

  const SecretKeyRevealDialog({
    super.key,
    required this.projectName,
    required this.label,
    required this.secret,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);
    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 480),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(FluentIcons.completed, size: 18, color: colors.successFg),
              const SizedBox(width: AdminSpacing.x8),
              Text(
                'Ключ создан',
                style: AdminTypography.sectionTitle.copyWith(
                  color: colors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: AdminSpacing.x4),
          Text(
            'Проект $projectName · метка «$label»',
            style: AdminTypography.bodySmall.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
      // Scrolling, like the quota dialogs above, and for two reasons at once.
      // A bare `Column` defaults to `MainAxisSize.max`, and `ContentDialog`
      // hands its content a *loose* `Flexible` — a maximum height, not a tight
      // one — so such a column takes the whole of it and the dialog stands as
      // tall as the window whatever it is holding. And a window short enough
      // that the content really does not fit should scroll rather than
      // overflow (`test/features/resources/dialog_layout_test.dart`).
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AdminBanner(
              message:
                  'Значение показывается только один раз. После закрытия окна '
                  'оно нигде не будет доступно — сохраните его сейчас.',
              tone: AdminBannerTone.error,
            ),
            const SizedBox(height: AdminSpacing.x14),
            Container(
              padding: const EdgeInsets.all(AdminSpacing.x12),
              decoration: BoxDecoration(
                color: colors.cardBg,
                border: Border.all(color: colors.border),
                borderRadius: BorderRadius.circular(AdminRadius.control),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      secret,
                      style: AdminTypography.monoSmall.copyWith(
                        color: colors.text,
                      ),
                    ),
                  ),
                  const SizedBox(width: AdminSpacing.x8),
                  IconButton(
                    icon: const Icon(FluentIcons.copy, size: 16),
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: secret)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        AdminButton(
          label: 'Я сохранил(а) ключ — закрыть',
          variant: AdminButtonVariant.accent,
          size: AdminButtonSize.dialog,
          onPressed: onClose,
        ),
      ],
    );
  }
}

/// One field and a name for it. Used for the group and the secret key, which
/// the server asks nothing else about.
class NameDialog extends StatefulWidget {
  final String title;
  final String fieldLabel;
  final String confirmLabel;
  final String? description;
  final bool submitting;
  final String? errorText;
  final ValueChanged<String> onSubmit;
  final VoidCallback onCancel;

  const NameDialog({
    super.key,
    required this.title,
    required this.fieldLabel,
    required this.confirmLabel,
    required this.onSubmit,
    required this.onCancel,
    this.description,
    this.submitting = false,
    this.errorText,
  });

  @override
  State<NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<NameDialog> {
  final _value = TextEditingController();

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);
    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 440),
      title: Text(
        widget.title,
        style: AdminTypography.sectionTitle.copyWith(color: colors.text),
      ),
      // Scrolling, like the quota dialogs above, and for two reasons at once.
      // A bare `Column` defaults to `MainAxisSize.max`, and `ContentDialog`
      // hands its content a *loose* `Flexible` — a maximum height, not a tight
      // one — so such a column takes the whole of it and the dialog stands as
      // tall as the window whatever it is holding. And a window short enough
      // that the content really does not fit should scroll rather than
      // overflow (`test/features/resources/dialog_layout_test.dart`).
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
              label: widget.fieldLabel,
              controller: _value,
              autofocus: true,
              onSubmitted: () => widget.onSubmit(_value.text.trim()),
            ),
            if (widget.description != null) ...[
              const SizedBox(height: AdminSpacing.x10),
              Text(
                widget.description!,
                style: AdminTypography.caption.copyWith(
                  color: colors.textSecondary,
                  height: 1.45,
                ),
              ),
            ],
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
          label: widget.confirmLabel,
          variant: AdminButtonVariant.accent,
          size: AdminButtonSize.dialog,
          onPressed: widget.submitting
              ? null
              : () => widget.onSubmit(_value.text.trim()),
        ),
      ],
    );
  }
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
  final Future<List<UserDto>> Function(String query) searchUsers;

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
        'Предоставить доступ',
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
              label: 'Имя получателя',
              placeholder: _subjectType == 'user'
                  ? 'Начните вводить имя пользователя…'
                  : 'Начните вводить название команды…',
              onSearch: (query) async {
                if (_subjectType == 'team') {
                  final teams = await widget.searchTeams(query);
                  return [
                    for (final t in teams)
                      AdminSearchPickerItem(value: t.id, label: t.name),
                  ];
                }
                final users = await widget.searchUsers(query);
                return [
                  for (final u in users)
                    AdminSearchPickerItem(value: u.id, label: u.username),
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
          label: 'Отмена',
          size: AdminButtonSize.dialog,
          onPressed: widget.submitting ? null : widget.onCancel,
        ),
        AdminButton(
          label: 'Предоставить',
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
          'Получатель',
          style: AdminTypography.label.copyWith(color: colors.text),
        ),
        const SizedBox(height: AdminSpacing.x6),
        ComboBox<String>(
          value: value,
          isExpanded: true,
          items: const [
            ComboBoxItem(value: 'user', child: Text('Пользователь')),
            ComboBoxItem(value: 'team', child: Text('Команда')),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ],
    );
  }
}

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
  final List<TeamMemberDto> members;
  final bool loading;
  final bool changing;
  final String? errorText;
  final Future<List<UserDto>> Function(String query) searchUsers;
  final ValueChanged<int> onAdd;
  final ValueChanged<int> onRemove;
  final VoidCallback onClose;

  const TeamMembersDialog({
    super.key,
    required this.teamName,
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
      title: Text(
        'Состав команды «${widget.teamName}»',
        style: AdminTypography.sectionTitle.copyWith(color: colors.text),
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
                  // exposes neither.
                  child: AdminSearchPicker<int>(
                    key: ValueKey(memberIds.toList()..sort()),
                    label: 'Добавить участника',
                    placeholder: 'Начните вводить имя пользователя…',
                    enabled: !widget.changing,
                    onSearch: (query) async {
                      final users = await widget.searchUsers(query);
                      return [
                        for (final u in users)
                          if (!memberIds.contains(u.id))
                            AdminSearchPickerItem(
                              value: u.id,
                              label: u.username,
                            ),
                      ];
                    },
                    onSelected: (item) =>
                        setState(() => _candidateId = item?.value),
                  ),
                ),
                const SizedBox(width: AdminSpacing.x10),
                AdminButton(
                  label: 'Добавить',
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
              const AdminEmptyState(
                icon: FluentIcons.contact,
                title: 'Участников пока нет',
                description: 'Добавьте первого через поиск выше.',
              )
            else
              for (final member in widget.members) ...[
                AdminResourceRow(
                  icon: FluentIcons.contact,
                  title: member.username,
                  actions: [
                    AdminButton(
                      label: 'Удалить',
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
          label: 'Закрыть',
          variant: AdminButtonVariant.accent,
          size: AdminButtonSize.dialog,
          onPressed: widget.onClose,
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
        Text('Роль', style: AdminTypography.label.copyWith(color: colors.text)),
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
