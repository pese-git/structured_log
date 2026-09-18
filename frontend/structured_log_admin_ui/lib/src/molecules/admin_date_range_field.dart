import 'package:fluent_ui/fluent_ui.dart';

import '../tokens/tokens.dart';

/// The two ends of a time range, as `AuditLog.dc.html` draws them: two boxes
/// reading "С: 01 сен" and "По: 13 сен", side by side in the filter row.
///
/// Two independent bounds rather than one range control, because that is the
/// question an operator actually asks — "since Monday", "up to the incident" —
/// and either end alone is a legitimate filter. A range picker would insist on
/// both.
///
/// Holds no value of its own: the dates come in, changes go out, and the screen
/// owns the state, like every other control in this kit (`design.md` decision
/// 39). Only the flyout is internal.
class AdminDateRangeField extends StatelessWidget {
  /// `null` leaves that end open, and the box says so instead of showing a
  /// date nobody picked.
  final DateTime? from;
  final DateTime? to;

  final ValueChanged<DateTime?> onFromChanged;
  final ValueChanged<DateTime?> onToChanged;

  /// Renders a chosen date. The kit does not decide the format, for the same
  /// reason [AdminLogEntryRow] takes its time already formatted: how much of a
  /// date is worth showing depends on the range on screen, and formatting a
  /// date for a human needs a locale this package does not carry.
  final String Function(DateTime) formatDate;

  /// The prefixes the canvas puts in front of each box, and the word an open
  /// end reads as.
  final String fromLabel;
  final String toLabel;
  final String anyLabel;

  /// The command at the foot of the flyout that reopens that end.
  final String clearLabel;

  const AdminDateRangeField({
    super.key,
    required this.onFromChanged,
    required this.onToChanged,
    required this.formatDate,
    this.from,
    this.to,
    this.fromLabel = 'From',
    this.toLabel = 'To',
    this.anyLabel = 'any',
    this.clearLabel = 'Any date',
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Bound(
          prefix: fromLabel,
          value: from,
          anyLabel: anyLabel,
          clearLabel: clearLabel,
          formatDate: formatDate,
          // An end date is never earlier than a start date, and saying so in
          // the calendar is kinder than reporting an empty result afterwards.
          maxDate: to,
          onChanged: onFromChanged,
        ),
        const SizedBox(width: AdminSpacing.x8),
        _Bound(
          prefix: toLabel,
          value: to,
          anyLabel: anyLabel,
          clearLabel: clearLabel,
          formatDate: formatDate,
          minDate: from,
          onChanged: onToChanged,
        ),
      ],
    );
  }
}

/// One end: the canvas's box, with a calendar hanging off it.
class _Bound extends StatefulWidget {
  final String prefix;
  final DateTime? value;
  final String anyLabel;
  final String clearLabel;
  final String Function(DateTime) formatDate;
  final DateTime? minDate;
  final DateTime? maxDate;
  final ValueChanged<DateTime?> onChanged;

  const _Bound({
    required this.prefix,
    required this.value,
    required this.anyLabel,
    required this.clearLabel,
    required this.formatDate,
    required this.onChanged,
    this.minDate,
    this.maxDate,
  });

  @override
  State<_Bound> createState() => _BoundState();
}

class _BoundState extends State<_Bound> {
  final _flyout = FlyoutController();

  @override
  void dispose() {
    _flyout.dispose();
    super.dispose();
  }

  void _open() {
    _flyout.showFlyout<void>(
      // Under the box, like the artboards draw it; the default placement
      // picked "above" and covered the toolbar the box sits in.
      placementMode: FlyoutPlacementMode.bottomLeft,
      barrierColor: Colors.transparent,
      additionalOffset: AdminSpacing.x8,
      builder: (context) {
        final colors = AdminColors.of(FluentTheme.of(context).brightness);
        return FlyoutContent(
          padding: const EdgeInsets.all(AdminSpacing.x8),
          // A fixed width: `stretch` would otherwise take everything the
          // flyout is offered, which is the whole window.
          child: SizedBox(
            width: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 340,
                  child: CalendarView(
                    initialStart: widget.value,
                    minDate: widget.minDate,
                    maxDate: widget.maxDate,
                    onSelectionChanged: (selection) {
                      final picked = selection.selectedDates.isEmpty
                          ? null
                          : selection.selectedDates.first;
                      Navigator.of(context).pop();
                      widget.onChanged(picked);
                    },
                  ),
                ),
                const SizedBox(height: AdminSpacing.x8),
                // Reopening the end has to be reachable from here: without it a
                // reader who once picked a date can only move it, never take it
                // back, and "since Monday, up to whenever" becomes unaskable.
                Button(
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onChanged(null);
                  },
                  child: Text(
                    widget.clearLabel,
                    style: AdminTypography.bodySmall.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);
    final value = widget.value;

    return FlyoutTarget(
      controller: _flyout,
      child: HoverButton(
        onPressed: _open,
        builder: (context, states) {
          return Container(
            height: AdminSizes.controlHeight,
            padding: const EdgeInsets.symmetric(horizontal: AdminSpacing.x10),
            decoration: BoxDecoration(
              color: states.isHovered ? colors.cardBg : colors.surface,
              border: Border.all(color: colors.borderStrong),
              borderRadius: BorderRadius.circular(AdminRadius.control),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  FluentIcons.calendar,
                  size: 14,
                  color: colors.textTertiary,
                ),
                const SizedBox(width: AdminSpacing.x6),
                Text(
                  '${widget.prefix}: '
                  '${value == null ? widget.anyLabel : widget.formatDate(value)}',
                  style: AdminTypography.bodySmall.copyWith(
                    color: value == null ? colors.textTertiary : colors.text,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
