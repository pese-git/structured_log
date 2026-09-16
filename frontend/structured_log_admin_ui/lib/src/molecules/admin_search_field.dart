import 'package:fluent_ui/fluent_ui.dart';

import '../tokens/tokens.dart';

/// The search input that opens a list screen and the log feed's filter bar.
///
/// Wraps Fluent's [TextBox] and gives it the canvas's box treatment: 32 high,
/// outlined, with the magnifier inside the field rather than beside it.
///
/// The clear affordance is **not** in the canvas — the mockups only ever draw
/// the resting, empty state. It appears once there is something to clear,
/// which is the behaviour a search field is expected to have; if a later
/// artboard says otherwise, that wins.
class AdminSearchField extends StatelessWidget {
  final TextEditingController controller;
  final String placeholder;
  final ValueChanged<String>? onChanged;

  /// Called when the reader presses Enter.
  ///
  /// Exists because not every search is cheap enough to run per keystroke: a
  /// query that resets pagination, or one the server runs as a LIKE over
  /// stored JSON, should happen when the reader says they are done typing —
  /// and a half-typed value is a different question from the whole one.
  final ValueChanged<String>? onSubmitted;

  /// Called when the field is cleared through its own button. The text is
  /// cleared first, so a listener on [controller] sees the empty value either
  /// way; this exists for callers that act on clearing itself.
  final VoidCallback? onCleared;

  const AdminSearchField({
    super.key,
    required this.controller,
    required this.placeholder,
    this.onChanged,
    this.onSubmitted,
    this.onCleared,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);
    return SizedBox(
      height: AdminSizes.controlHeight,
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) {
          return TextBox(
            controller: controller,
            placeholder: placeholder,
            onChanged: onChanged,
            onSubmitted: onSubmitted,
            style: AdminTypography.bodySmall.copyWith(color: colors.text),
            placeholderStyle: AdminTypography.bodySmall.copyWith(
              color: colors.textTertiary,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AdminSpacing.x8,
              vertical: AdminSpacing.x6,
            ),
            decoration: WidgetStateProperty.all(
              BoxDecoration(
                color: colors.surface,
                border: Border.all(color: colors.borderStrong),
                borderRadius: BorderRadius.circular(AdminRadius.control),
              ),
            ),
            prefix: Padding(
              padding: const EdgeInsets.only(left: AdminSpacing.x10),
              child: Icon(
                FluentIcons.search,
                size: 15,
                color: colors.textTertiary,
              ),
            ),
            suffix: value.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(FluentIcons.clear, size: 11),
                    onPressed: () {
                      controller.clear();
                      onChanged?.call('');
                      onCleared?.call();
                    },
                  ),
          );
        },
      ),
    );
  }
}
