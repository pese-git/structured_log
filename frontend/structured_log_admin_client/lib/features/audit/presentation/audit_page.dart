import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:structured_log_admin_ui/structured_log_admin_ui.dart';

import '../../../l10n/formatting.dart';
import '../../../l10n/l10n.dart';
import '../../../shared/api/dto/audit_dto.dart';
import 'audit_action_labels.dart';
import 'audit_cubit.dart';
import 'audit_failure_text.dart';
import 'audit_metadata_view.dart';

/// The audit log (`AuditLog.dc.html`).
///
/// Administrative acts and authentication events in one table, under one set of
/// filters — the spec is explicit that the two are not separate screens
/// (`specs/admin-client-audit-log`): an operator investigating an incident is
/// asking one question, and a login that preceded a change is part of the
/// answer.
///
/// Nothing here decides access. The section is offered only to a token that
/// carries the global admin role, but the authority is the server's 403, which
/// this screen renders as a refusal rather than as a failure to load.
class AuditPage extends StatefulWidget {
  const AuditPage({super.key});

  @override
  State<AuditPage> createState() => _AuditPageState();
}

class _AuditPageState extends State<AuditPage> {
  final _targetId = TextEditingController();
  final _actorId = TextEditingController();

  @override
  void initState() {
    super.initState();
    // `HomeShell._openAuditFor` (`UserDetailPage`'s "Открыть в аудите"
    // link) applies the actor filter on the cubit before this page is ever
    // built, so the query is already right — this only seeds the field's
    // own text to match, since it is a local controller the cubit's state
    // does not drive.
    final actorId = context.read<AuditCubit>().state.filter.actorUserId;
    if (actorId != null) _actorId.text = actorId.toString();
  }

  @override
  void dispose() {
    _targetId.dispose();
    _actorId.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);

    return BlocBuilder<AuditCubit, AuditState>(
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
              Text(
                context.l10n.auditTitle,
                style: AdminTypography.pageTitle.copyWith(color: colors.text),
              ),
              const SizedBox(height: AdminSpacing.x4),
              Text(
                context.l10n.auditSubtitle,
                style: AdminTypography.bodySmall.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              if (state.loaded) ...[
                const SizedBox(height: AdminSpacing.x12),
                _RetentionStrip(state: state),
              ],
              const SizedBox(height: AdminSpacing.x14),
              _filters(context, state),
              Expanded(child: _body(context, state)),
            ],
          ),
        );
      },
    );
  }

  Widget _filters(BuildContext context, AuditState state) {
    final cubit = context.read<AuditCubit>();
    final filter = state.filter;

    return AdminFilterBar(
      filters: [
        SizedBox(
          width: 210,
          child: _ActionPicker(
            selected: filter.action,
            onChanged: (action) =>
                cubit.applyFilter(filter.copyWith(action: action)),
          ),
        ),
        SizedBox(
          width: 190,
          child: _TargetTypePicker(
            selected: filter.targetType,
            onChanged: (type) =>
                cubit.applyFilter(filter.copyWith(targetType: type)),
          ),
        ),
        SizedBox(
          width: 150,
          child: AdminSearchField(
            controller: _targetId,
            placeholder: context.l10n.auditFilterTargetId,
            // On submit, not per keystroke: every change is a new query from
            // the first page, and `1` on the way to `17` is a different
            // record, not a prefix of one.
            onSubmitted: (value) =>
                cubit.applyFilter(filter.copyWith(targetId: _id(value))),
            onCleared: () => cubit.applyFilter(filter.copyWith(targetId: null)),
          ),
        ),
        SizedBox(
          width: 150,
          child: AdminSearchField(
            controller: _actorId,
            placeholder: context.l10n.auditFilterActorId,
            onSubmitted: (value) =>
                cubit.applyFilter(filter.copyWith(actorUserId: _id(value))),
            onCleared: () =>
                cubit.applyFilter(filter.copyWith(actorUserId: null)),
          ),
        ),
        AdminDateRangeField(
          from: filter.from,
          to: filter.to,
          formatDate: (date) => formatDayMonth(context.l10n, date),
          fromLabel: context.l10n.auditDateFrom,
          toLabel: context.l10n.auditDateTo,
          anyLabel: context.l10n.auditDateAny,
          clearLabel: context.l10n.auditDateClear,
          onFromChanged: (value) =>
              cubit.applyFilter(filter.copyWith(from: value)),
          onToChanged: (value) => cubit.applyFilter(filter.copyWith(to: value)),
        ),
      ],
      trailing: [
        if (filter.isActive)
          AdminButton(
            label: context.l10n.auditFilterReset,
            icon: FluentIcons.clear_filter,
            onPressed: () {
              _targetId.clear();
              _actorId.clear();
              cubit.clearFilters();
            },
          ),
      ],
    );
  }

  /// An id, or `null` for anything that is not one.
  ///
  /// A non-numeric value clears the filter rather than failing the request:
  /// these boxes take an id because that is all a record carries, and typing a
  /// name into one should widen the query, not break it.
  int? _id(String value) => int.tryParse(value.trim());

  Widget _body(BuildContext context, AuditState state) {
    if (state.loading) {
      return const Center(child: AdminLoadingIndicator());
    }
    if (state.failure != null && state.entries.isEmpty) {
      return AdminEmptyState(
        icon: FluentIcons.error_badge,
        title: context.l10n.auditLoadFailedTitle,
        description: describeAuditFailure(context.l10n, state.failure!),
      );
    }
    if (state.isEmptyByRetention) {
      return AdminEmptyState(
        icon: FluentIcons.history,
        title: context.l10n.auditPurgedTitle,
        description: context.l10n.auditPurgedDescription(
          describeRetention(context.l10n, state.authEventRetentionDays),
          describeRetention(context.l10n, state.auditRetentionDays),
        ),
      );
    }
    if (state.isEmpty) {
      return AdminEmptyState(
        icon: FluentIcons.text_document,
        title: state.filter.isActive
            ? context.l10n.auditNothingFoundTitle
            : context.l10n.auditEmptyTitle,
        description: state.filter.isActive
            ? context.l10n.auditNothingFoundDescription
            : context.l10n.auditEmptyDescription,
      );
    }

    return ListView(
      children: [
        _table(context, state),
        if (state.hasMore)
          Padding(
            padding: const EdgeInsets.all(AdminSpacing.x18),
            child: Center(
              child: state.loadingMore
                  ? const AdminLoadingIndicator()
                  : AdminButton(
                      label: context.l10n.auditLoadMore,
                      icon: FluentIcons.chevron_down,
                      onPressed: context.read<AuditCubit>().loadMore,
                    ),
            ),
          ),
      ],
    );
  }

  Widget _table(BuildContext context, AuditState state) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);

    return AdminTable(
      columns: [
        AdminColumn(context.l10n.auditColumnTime, width: 128),
        AdminColumn(context.l10n.auditColumnActor, width: 150),
        AdminColumn(context.l10n.auditColumnAction, width: 196),
        AdminColumn(context.l10n.auditColumnTarget, width: 210),
        AdminColumn.flexible(context.l10n.auditColumnDetails),
      ],
      rows: [
        for (final entry in state.entries)
          _row(context, entry, colors, AuditAction.fromWire(entry.action)),
      ],
    );
  }

  AdminTableRow _row(
    BuildContext context,
    AuditEntryDto entry,
    AdminColors colors,
    AuditAction? action,
  ) {
    final actor = auditActorText(context.l10n, entry);

    return AdminTableRow(
      // The canvas tints the two records that are about the system rather than
      // about a person, so they read as a different kind of line.
      background: switch (action) {
        AuditAction.authThrottled => colors.warnBg,
        AuditAction.auditPurged => colors.cardBg,
        _ => null,
      },
      cells: [
        Text(
          formatAuditTime(entry.createdAt),
          style: AdminTypography.monoSmall.copyWith(color: colors.textTertiary),
        ),
        Text(
          actor.text,
          style: AdminTypography.bodySmall.copyWith(
            color: actor.absent ? colors.textTertiary : colors.text,
            fontStyle: actor.absent ? FontStyle.italic : FontStyle.normal,
          ),
        ),
        _ActionTag(wire: entry.action, action: action),
        Text(
          auditTargetText(context.l10n, entry),
          style: AdminTypography.bodySmall.copyWith(color: colors.text),
        ),
        AuditMetadataView(metadata: entry.metadata),
      ],
    );
  }
}

/// The two retention periods, and the note that a purge is itself a record.
class _RetentionStrip extends StatelessWidget {
  final AuditState state;

  const _RetentionStrip({required this.state});

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);

    return Wrap(
      spacing: AdminSpacing.x8,
      runSpacing: AdminSpacing.x8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // Both, never merged into one number: they are configured separately
        // and an operator who reads one as the other will look for records in
        // the wrong place (`specs/admin-client-audit-log`).
        AdminTag(
          label: context.l10n.auditRetentionAdminTag(
            describeRetention(context.l10n, state.auditRetentionDays),
          ),
        ),
        AdminTag(
          label: context.l10n.auditRetentionAuthTag(
            describeRetention(context.l10n, state.authEventRetentionDays),
          ),
        ),
        Text(
          context.l10n.auditRetentionNote,
          style: AdminTypography.caption.copyWith(color: colors.textTertiary),
        ),
      ],
    );
  }
}

/// The action cell.
///
/// Shows the wire value, which is what the reader filters by and what the API
/// documents; the localized name is the tooltip, because a tag wide enough for
/// both would not fit the column the artboard draws.
class _ActionTag extends StatelessWidget {
  final String wire;
  final AuditAction? action;

  const _ActionTag({required this.wire, this.action});

  @override
  Widget build(BuildContext context) {
    final tag = AdminStatusTag(
      label: wire,
      tone: action == null ? AdminStatusTone.neutral : auditActionTone(action!),
    );

    // A record from a newer server than this bundle knows about is still
    // shown, with its raw value and no name: an audit log may not hide a row
    // it fails to recognise.
    if (action == null) return tag;
    return Tooltip(
      message: auditActionLabel(context.l10n, action!),
      child: tag,
    );
  }
}

class _ActionPicker extends StatelessWidget {
  final AuditAction? selected;
  final ValueChanged<AuditAction?> onChanged;

  const _ActionPicker({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return ComboBox<AuditAction?>(
      value: selected,
      placeholder: Text(context.l10n.auditFilterActionAny),
      isExpanded: true,
      items: [
        ComboBoxItem<AuditAction?>(
          value: null,
          child: Text(context.l10n.auditFilterActionAny),
        ),
        for (final action in AuditAction.values)
          ComboBoxItem<AuditAction?>(
            value: action,
            // Both, in the menu: the name is what makes twenty-five options
            // scannable, and the wire value is what the reader will recognise
            // from the table they are filtering.
            child: Text(
              '${auditActionLabel(context.l10n, action)} · ${action.wire}',
            ),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

class _TargetTypePicker extends StatelessWidget {
  final AuditTargetType? selected;
  final ValueChanged<AuditTargetType?> onChanged;

  const _TargetTypePicker({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return ComboBox<AuditTargetType?>(
      value: selected,
      placeholder: Text(context.l10n.auditFilterTargetTypeAny),
      isExpanded: true,
      items: [
        ComboBoxItem<AuditTargetType?>(
          value: null,
          child: Text(context.l10n.auditFilterTargetTypeAny),
        ),
        for (final type in AuditTargetType.values)
          ComboBoxItem<AuditTargetType?>(
            value: type,
            child: Text(auditTargetTypeLabel(context.l10n, type)),
          ),
      ],
      onChanged: onChanged,
    );
  }
}
