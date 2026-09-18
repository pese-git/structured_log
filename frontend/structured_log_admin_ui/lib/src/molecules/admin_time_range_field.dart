import 'package:fluent_ui/fluent_ui.dart';

import '../tokens/tokens.dart';

/// The two ends of a time-of-day range, as `LogBrowser.dc.html` draws them:
/// two boxes reading "С: 09:00" and "По: 10:00", side by side in the filter
/// row.
///
/// Time-of-day only, not a date — unlike [AdminDateRangeField]
/// (`AuditLog.dc.html`'s day-granularity "С: 01 сен"), this artboard never
/// shows a date component at all. The log feed is a live/recent-activity
/// view, not a day-spanning journal, so a bound this control produces
/// applies to the current local day: picking a time combines it with
/// today's date (or, if [from]/[to] is already set, that bound's own date)
/// into the `DateTime` handed back. A multi-day range is a different
/// question than the one the canvas asks here.
///
/// Two independent bounds and a picker with an explicit confirm step,
/// because hour and minute are two choices that both need making before a
/// bound means anything — unlike [AdminDateRangeField]'s single-tap
/// calendar day, applying immediately here would commit on the first of the
/// two picks.
///
/// Holds no value of its own: the times come in, changes go out, and the
/// screen owns the state, like every other control in this kit (`design.md`
/// decision 39). Only the flyout is internal.
class AdminTimeRangeField extends StatelessWidget {
  /// `null` leaves that end open, and the box says so instead of showing a
  /// time nobody picked.
  final DateTime? from;
  final DateTime? to;

  final ValueChanged<DateTime?> onFromChanged;
  final ValueChanged<DateTime?> onToChanged;

  /// Renders a chosen bound as the box's own text — "09:00". The kit does
  /// not decide the format, for the same reason [AdminDateRangeField]'s own
  /// `formatDate` doesn't: formatting a time for a human needs a locale
  /// this package does not carry.
  final String Function(DateTime) formatTime;

  /// The prefixes the canvas puts in front of each box, and the word an
  /// open end reads as.
  final String fromLabel;
  final String toLabel;
  final String anyLabel;

  /// The flyout's two footer commands.
  final String clearLabel;
  final String applyLabel;

  const AdminTimeRangeField({
    super.key,
    required this.onFromChanged,
    required this.onToChanged,
    required this.formatTime,
    this.from,
    this.to,
    this.fromLabel = 'From',
    this.toLabel = 'To',
    this.anyLabel = 'any',
    this.clearLabel = 'Any time',
    this.applyLabel = 'Apply',
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
          applyLabel: applyLabel,
          formatTime: formatTime,
          onChanged: onFromChanged,
        ),
        const SizedBox(width: AdminSpacing.x8),
        _Bound(
          prefix: toLabel,
          value: to,
          anyLabel: anyLabel,
          clearLabel: clearLabel,
          applyLabel: applyLabel,
          formatTime: formatTime,
          onChanged: onToChanged,
        ),
      ],
    );
  }
}

/// One end: the canvas's box, with an hour/minute picker hanging off it.
class _Bound extends StatefulWidget {
  final String prefix;
  final DateTime? value;
  final String anyLabel;
  final String clearLabel;
  final String applyLabel;
  final String Function(DateTime) formatTime;
  final ValueChanged<DateTime?> onChanged;

  const _Bound({
    required this.prefix,
    required this.value,
    required this.anyLabel,
    required this.clearLabel,
    required this.applyLabel,
    required this.formatTime,
    required this.onChanged,
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
    // Staged locally until "Apply" — unlike the calendar day in
    // AdminDateRangeField, a single pick (just the hour, say) does not make
    // a bound worth committing.
    final anchor = widget.value ?? DateTime.now();
    var hour = anchor.hour;
    var minute = anchor.minute;

    _flyout.showFlyout<void>(
      barrierColor: Colors.transparent,
      additionalOffset: AdminSpacing.x8,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setFlyoutState) {
            final colors = AdminColors.of(FluentTheme.of(context).brightness);
            return FlyoutContent(
              padding: const EdgeInsets.all(AdminSpacing.x8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 180,
                    child: Row(
                      children: [
                        Expanded(
                          child: ComboBox<int>(
                            value: hour,
                            isExpanded: true,
                            items: [
                              for (var h = 0; h < 24; h++)
                                ComboBoxItem(value: h, child: Text(_two(h))),
                            ],
                            onChanged: (v) {
                              if (v != null) setFlyoutState(() => hour = v);
                            },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AdminSpacing.x6,
                          ),
                          child: Text(
                            ':',
                            style: AdminTypography.body.copyWith(
                              color: colors.text,
                            ),
                          ),
                        ),
                        Expanded(
                          child: ComboBox<int>(
                            value: minute,
                            isExpanded: true,
                            items: [
                              for (var m = 0; m < 60; m++)
                                ComboBoxItem(value: m, child: Text(_two(m))),
                            ],
                            onChanged: (v) {
                              if (v != null) setFlyoutState(() => minute = v);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AdminSpacing.x8),
                  Row(
                    children: [
                      Expanded(
                        child: Button(
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
                      ),
                      const SizedBox(width: AdminSpacing.x8),
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            widget.onChanged(
                              DateTime(
                                anchor.year,
                                anchor.month,
                                anchor.day,
                                hour,
                                minute,
                              ),
                            );
                          },
                          child: Text(widget.applyLabel),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

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
                Icon(FluentIcons.clock, size: 14, color: colors.textTertiary),
                const SizedBox(width: AdminSpacing.x6),
                Text(
                  '${widget.prefix}: '
                  '${value == null ? widget.anyLabel : widget.formatTime(value)}',
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
