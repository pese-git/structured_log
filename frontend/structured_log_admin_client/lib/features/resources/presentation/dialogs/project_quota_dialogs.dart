import 'package:fluent_ui/fluent_ui.dart';
import 'package:structured_log_admin_ui/structured_log_admin_ui.dart';
import '../../../../l10n/l10n.dart';

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
              context.l10n.resNoLimit,
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
          label: context.l10n.resFieldRetention,
          controller: retention,
        ),
        const SizedBox(height: AdminSpacing.x14),
        _LimitField(
          label: context.l10n.resFieldMaxEntries,
          controller: entries,
          unlimited: entriesUnlimited,
          onUnlimitedChanged: onEntriesUnlimited,
        ),
        const SizedBox(height: AdminSpacing.x14),
        _LimitField(
          label: context.l10n.resFieldMaxBytes,
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
        context.l10n.resNewProject,
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
              context.l10n.resGroup,
              style: AdminTypography.bodySmall.copyWith(color: colors.text),
            ),
            const SizedBox(height: AdminSpacing.x6),
            AdminTag(label: widget.groupName),
            const SizedBox(height: AdminSpacing.x14),
            AdminTextField(
              label: context.l10n.resProjectNameLabel,
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
              context.l10n.resNewProjectNote,
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
          label: context.l10n.resCancel,
          size: AdminButtonSize.dialog,
          onPressed: widget.submitting ? null : widget.onCancel,
        ),
        AdminButton(
          label: context.l10n.resCreateProject,
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
            context.l10n.resEditQuota,
            style: AdminTypography.sectionTitle.copyWith(color: colors.text),
          ),
          const SizedBox(height: AdminSpacing.x4),
          Text(
            context.l10n.resProjectPrefix(widget.projectName),
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
          label: context.l10n.resCancel,
          size: AdminButtonSize.dialog,
          onPressed: widget.submitting ? null : widget.onCancel,
        ),
        AdminButton(
          label: context.l10n.resSave,
          variant: AdminButtonVariant.accent,
          size: AdminButtonSize.dialog,
          onPressed: widget.submitting ? null : _submit,
        ),
      ],
    );
  }
}
