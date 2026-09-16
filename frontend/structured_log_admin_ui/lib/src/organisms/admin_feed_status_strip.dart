import 'package:fluent_ui/fluent_ui.dart';

import '../atoms/admin_button.dart';
import '../atoms/admin_loading_indicator.dart';
import '../molecules/admin_live_pill.dart';
import '../tokens/tokens.dart';

enum _StripKind { live, unseen, held, stalled, loadingOlder }

/// The strip the log feed wears at the edge of its list.
///
/// `LogBrowser.dc.html` draws five of them and never two at once: what the
/// feed is doing right now is one fact. They share a frame — full width, a
/// hairline against the list, 12px text — and differ in tone and in what they
/// offer, so they are one component with five constructors rather than five
/// widgets that would drift apart.
///
/// Four sit under the list; [AdminFeedStatusStrip.loadingOlder] sits above it,
/// which is the only reason the hairline can change sides.
class AdminFeedStatusStrip extends StatelessWidget {
  final _StripKind _kind;

  final String message;

  /// The second line of [AdminFeedStatusStrip.stalled] — why the feed cannot
  /// simply continue.
  final String? description;

  final String? actionLabel;
  final VoidCallback? onAction;

  /// Following the newest entries: a quiet line saying where they appear.
  const AdminFeedStatusStrip.live({super.key, required this.message})
      : _kind = _StripKind.live,
        description = null,
        actionLabel = null,
        onAction = null;

  /// Entries have arrived below the fold. The whole strip is the way back to
  /// them, so [message] carries the count — "12 новых записей · перейти к
  /// свежим".
  const AdminFeedStatusStrip.unseen({
    super.key,
    required this.message,
    required VoidCallback this.onAction,
  })  : _kind = _StripKind.unseen,
        description = null,
        actionLabel = null;

  /// Explicitly paused, with what is waiting.
  const AdminFeedStatusStrip.held({
    super.key,
    required this.message,
    required String this.actionLabel,
    required VoidCallback this.onAction,
  })  : _kind = _StripKind.held,
        description = null;

  /// The feed cannot continue as it was: a pause that outgrew its buffer, or
  /// a subscription the server closed for good.
  const AdminFeedStatusStrip.stalled({
    super.key,
    required this.message,
    required String this.description,
    required String this.actionLabel,
    required VoidCallback this.onAction,
  }) : _kind = _StripKind.stalled;

  /// An older page is on its way in at the top of the list.
  const AdminFeedStatusStrip.loadingOlder({super.key, required this.message})
      : _kind = _StripKind.loadingOlder,
        description = null,
        actionLabel = null,
        onAction = null;

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);

    final background = switch (_kind) {
      _StripKind.live => colors.cardBg,
      _StripKind.unseen => colors.accentTint,
      _StripKind.held || _StripKind.stalled => colors.warnBg,
      _StripKind.loadingOlder => colors.cardBg,
    };
    final edge = switch (_kind) {
      _StripKind.unseen => colors.accent,
      _ => colors.border,
    };
    final border = _kind == _StripKind.loadingOlder
        ? Border(bottom: BorderSide(color: edge))
        : Border(top: BorderSide(color: edge));

    return DecoratedBox(
      decoration: BoxDecoration(color: background, border: border),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AdminSpacing.x12,
          vertical: AdminSpacing.x10,
        ),
        child: switch (_kind) {
          _StripKind.live => _row([
              AdminLiveDot(color: colors.liveFg),
              const SizedBox(width: AdminSpacing.x10),
              Expanded(child: _text(message, colors.textSecondary)),
            ]),
          _StripKind.loadingOlder => _row(
              [
                const AdminLoadingIndicator(inline: true),
                const SizedBox(width: AdminSpacing.x8),
                Flexible(child: _text(message, colors.textSecondary)),
              ],
              centered: true,
            ),
          _StripKind.unseen => Center(
              child: AdminButton(
                label: message,
                icon: FluentIcons.chevron_down,
                variant: AdminButtonVariant.accent,
                size: AdminButtonSize.tonal,
                onPressed: onAction,
              ),
            ),
          _StripKind.held => _row([
              Icon(FluentIcons.pause, size: 14, color: colors.warnFg),
              const SizedBox(width: AdminSpacing.x10),
              Expanded(child: _text(message, colors.warnFg)),
              _link(colors),
            ]),
          _StripKind.stalled => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _row([
                  Icon(FluentIcons.warning, size: 14, color: colors.warnFg),
                  const SizedBox(width: AdminSpacing.x8),
                  Expanded(child: _text(message, colors.warnFg)),
                ]),
                const SizedBox(height: AdminSpacing.x6),
                _text(description!, colors.textSecondary, height: 1.45),
                const SizedBox(height: AdminSpacing.x6),
                _link(colors),
              ],
            ),
        },
      ),
    );
  }

  static Widget _row(List<Widget> children, {bool centered = false}) => Row(
        mainAxisAlignment:
            centered ? MainAxisAlignment.center : MainAxisAlignment.start,
        children: children,
      );

  static Widget _text(String value, Color color, {double? height}) => Text(
        value,
        style: AdminTypography.caption.copyWith(color: color, height: height),
      );

  Widget _link(AdminColors colors) => HyperlinkButton(
        onPressed: onAction,
        child: Text(
          actionLabel!,
          style: AdminTypography.caption.copyWith(color: colors.accent),
        ),
      );
}
