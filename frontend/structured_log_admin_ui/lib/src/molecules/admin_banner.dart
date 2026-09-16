import 'package:fluent_ui/fluent_ui.dart';

import '../tokens/tokens.dart';

/// What a banner is saying.
///
/// Its own scale rather than [AdminStatusTone]'s: a status tag reports the
/// state of a thing (active, blocked), a banner reports what just happened to
/// a request — and needs a neutral-informative tone, drawn in the accent tint,
/// that a status tag has no use for.
enum AdminBannerTone { info, warning, error }

/// The message above a form: why the last attempt failed, or what to do next.
///
/// Tinted ground, no outline, no dismiss button — the artboards show these
/// appearing and disappearing with the condition they describe, not being
/// closed by hand.
class AdminBanner extends StatelessWidget {
  final String message;
  final AdminBannerTone tone;

  /// An offer that belongs to the message — "отправить письмо ещё раз". Sits
  /// under the text, aligned with it.
  final Widget? action;

  const AdminBanner({
    super.key,
    required this.message,
    this.tone = AdminBannerTone.info,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);
    final (background, icon, iconColor) = switch (tone) {
      AdminBannerTone.info => (
          colors.accentTint,
          FluentIcons.info,
          colors.accentDark,
        ),
      AdminBannerTone.warning => (
          colors.warnBg,
          FluentIcons.warning,
          colors.warnFg,
        ),
      AdminBannerTone.error => (
          colors.errorBg,
          FluentIcons.error_badge,
          colors.errorFg,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AdminSpacing.x12,
        vertical: AdminSpacing.x10,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AdminRadius.control),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: AdminSpacing.x2),
            child: Icon(icon, size: 16, color: iconColor),
          ),
          const SizedBox(width: AdminSpacing.x10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: AdminTypography.bodySmall.copyWith(
                    color: colors.text,
                    height: 1.45,
                  ),
                ),
                if (action != null) ...[
                  const SizedBox(height: AdminSpacing.x8),
                  action!,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
