import 'package:flutter/services.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:structured_log_admin_ui/structured_log_admin_ui.dart';

import '../../../l10n/l10n.dart';
import '../../../shared/api/dto/log_dto.dart';
import 'log_level_mapping.dart';

/// One entry in full: the standard fields, then whatever the application
/// bound itself.
///
/// Lives in the client rather than in `structured_log_admin_ui` because it
/// takes an entry and decides which of its fields are standard — a component
/// in the library may only take primitives and callbacks (decision 39).
class LogEntryDetailPane extends StatelessWidget {
  final LogEntryDto entry;

  /// Closes the pane. Absent where the pane is permanent.
  final VoidCallback? onClose;

  const LogEntryDetailPane({super.key, required this.entry, this.onClose});

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AdminSpacing.x28,
        AdminSpacing.x24,
        AdminSpacing.x28,
        AdminSpacing.x24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        AdminLogLevelBadge(level: logLevelOf(entry.level)),
                        const SizedBox(width: AdminSpacing.x8),
                        Text(
                          entry.receivedAt.toLocal().toString(),
                          style: AdminTypography.monoSmall.copyWith(
                            color: colors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AdminSpacing.x8),
                    SelectableText(
                      entry.event,
                      style: AdminTypography.sectionTitle.copyWith(
                        color: colors.text,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AdminSpacing.x12),
              AdminButton(
                label: context.l10n.logsCopy,
                icon: FluentIcons.copy,
                size: AdminButtonSize.tonal,
                // The whole entry at once, as the spec asks: picking fields
                // out of a detail pane by hand is what this replaces.
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: _asText())),
              ),
              if (onClose != null) ...[
                const SizedBox(width: AdminSpacing.x8),
                IconButton(
                  icon: const Icon(FluentIcons.clear, size: 12),
                  onPressed: onClose,
                ),
              ],
            ],
          ),
          const SizedBox(height: AdminSpacing.x18),
          Divider(
            style: DividerThemeData(
              decoration: BoxDecoration(color: colors.border),
            ),
          ),
          const SizedBox(height: AdminSpacing.x18),
          _Section(
            title: context.l10n.logsStandardFields,
            rows: _standardRows(),
          ),
          if (entry.context.isNotEmpty) ...[
            const SizedBox(height: AdminSpacing.x18),
            // The point of the pane: fields the application chose, shown on
            // equal footing with the ones the server knows about.
            _Section(title: context.l10n.logsContext, rows: _contextRows()),
          ],
        ],
      ),
    );
  }

  List<AdminKeyValueRow> _standardRows() {
    return [
      AdminKeyValueRow(label: 'id', value: '${entry.id}', monospaceValue: true),
      AdminKeyValueRow(label: 'level', value: entry.level),
      AdminKeyValueRow(
        label: 'received_at',
        value: entry.receivedAt.toIso8601String(),
        monospaceValue: true,
      ),
      if (entry.timestamp != null)
        AdminKeyValueRow(
          label: 'timestamp',
          value: entry.timestamp!.toIso8601String(),
          monospaceValue: true,
        ),
      if (entry.category != null)
        AdminKeyValueRow(label: 'category', value: entry.category!),
      if (entry.logger != null)
        AdminKeyValueRow(label: 'logger', value: entry.logger!),
      // Correlation is standard, not arbitrary context — the spec lists it
      // among an entry's own fields.
      for (final row in <(String, String?)>[
        ('session_id', entry.sessionId),
        ('request_id', entry.requestId),
        ('tool_call_id', entry.toolCallId),
        ('message_id', entry.messageId),
        ('operation_id', entry.operationId),
        ('connection_generation', entry.connectionGeneration?.toString()),
      ])
        if (row.$2 != null)
          AdminKeyValueRow(label: row.$1, value: row.$2!, monospaceValue: true),
    ];
  }

  List<AdminKeyValueRow> _contextRows() {
    final keys = entry.context.keys.toList()..sort();
    return [
      for (final key in keys)
        AdminKeyValueRow(
          label: key,
          value: '${entry.context[key]}',
          monospaceValue: true,
        ),
    ];
  }

  String _asText() {
    final buffer = StringBuffer()
      ..writeln('${entry.level.toUpperCase()} ${entry.event}');
    for (final row in [..._standardRows(), ..._contextRows()]) {
      buffer.writeln('${row.label}: ${row.value}');
    }
    return buffer.toString();
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> rows;

  const _Section({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AdminTypography.caption.copyWith(
            color: colors.textTertiary,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: AdminSpacing.x12),
        ...rows,
      ],
    );
  }
}
