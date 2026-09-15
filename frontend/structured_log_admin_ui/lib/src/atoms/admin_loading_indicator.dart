import 'package:fluent_ui/fluent_ui.dart';

import '../tokens/tokens.dart';

/// The in-place busy indicator.
///
/// A thin wrapper on Fluent's [ProgressRing] that fixes the two sizes the
/// screens need — inside a control, and centred in a pane that is still
/// loading — so callers don't each pick their own.
class AdminLoadingIndicator extends StatelessWidget {
  /// Matches the height of the text it sits beside, for use inside a button or
  /// a row.
  final bool inline;

  /// Announced to screen readers while the ring spins.
  final String? semanticLabel;

  const AdminLoadingIndicator({
    super.key,
    this.inline = false,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);
    final size = inline ? 16.0 : 32.0;
    return SizedBox(
      width: size,
      height: size,
      child: ProgressRing(
        strokeWidth: inline ? 2 : 3,
        activeColor: colors.accent,
        semanticLabel: semanticLabel,
      ),
    );
  }
}
