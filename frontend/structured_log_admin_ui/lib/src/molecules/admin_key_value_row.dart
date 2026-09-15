import 'package:fluent_ui/fluent_ui.dart';

import '../tokens/tokens.dart';

/// One `key   value` line, as the log entry's context pane and the resource
/// detail screens draw them.
///
/// The key column is a fixed width so a stack of these lines up; the value
/// wraps rather than clipping, because `context` carries arbitrary payloads
/// and a truncated URL is worse than a two-line one.
class AdminKeyValueRow extends StatelessWidget {
  final String label;
  final String value;

  /// Draws the value in the monospaced face — for ids, keys, timestamps and
  /// anything else read character by character.
  final bool monospaceValue;

  /// The canvas sets this column to 140; a caller aligning several rows
  /// against a narrower pane can tighten it.
  final double labelWidth;

  const AdminKeyValueRow({
    super.key,
    required this.label,
    required this.value,
    this.monospaceValue = false,
    this.labelWidth = 140,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);
    return Padding(
      padding: const EdgeInsets.only(bottom: AdminSpacing.x14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: labelWidth,
            child: Text(
              label,
              style: AdminTypography.body.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style:
                  (monospaceValue ? AdminTypography.mono : AdminTypography.body)
                      .copyWith(color: colors.text),
            ),
          ),
        ],
      ),
    );
  }
}
