import 'package:fluent_ui/fluent_ui.dart';

import '../tokens/tokens.dart';

/// The row of controls above a list: a search field, the filter chips, and
/// whatever status or actions belong on the right.
///
/// Wraps onto further lines when the controls outgrow the width. That is not
/// an adaptive layout added here — `LogBrowser.dc.html` sets `flex-wrap:wrap`
/// on this very row, so wrapping is the drawn behaviour.
///
/// Carries only the gap between itself and the list below. The canvas also
/// shows a 24px gutter on either side, but that is the page's, not this
/// component's: a bar that padded itself could not sit in a pane with a
/// different gutter without being pulled back out again.
class AdminFilterBar extends StatelessWidget {
  /// Usually an `AdminSearchField`; any control fits.
  final Widget? leading;

  /// `AdminFilterChip`s, in the order the screen states them.
  final List<Widget> filters;

  /// Pushed to the end of the row when there is room: a live-status pill, a
  /// clear-all button.
  final List<Widget> trailing;

  const AdminFilterBar({
    super.key,
    this.leading,
    this.filters = const [],
    this.trailing = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AdminSpacing.x14),
      child: Wrap(
        spacing: AdminSpacing.x10,
        runSpacing: AdminSpacing.x10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (leading != null) SizedBox(width: 220, child: leading),
          ...filters,
          ...trailing,
        ],
      ),
    );
  }
}
