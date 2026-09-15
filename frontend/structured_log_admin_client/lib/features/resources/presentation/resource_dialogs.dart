import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:structured_log_admin_ui/structured_log_admin_ui.dart';

/// What a quota form produced. `null` in a limit means unlimited, and it is
/// sent as `null` rather than left out (`UpdateProjectQuotaRequestDto`).
typedef QuotaValues = ({int retentionDays, int? maxEntries, int? maxBytes});

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
