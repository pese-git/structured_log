import 'package:fluent_ui/fluent_ui.dart';

import '../tokens/tokens.dart';

/// One row in a list of users, projects, groups or keys.
///
/// Takes strings and callbacks only: which actions a row offers is the
/// caller's decision, made from the viewer's permissions, and an action the
/// current role may not take is expected to be absent here rather than
/// disabled — the screens hide what a role cannot do (`Users.dc.html`).
class AdminResourceRow extends StatelessWidget {
  final String title;

  /// A second line under the title — a project's group, a key's created-at.
  final String? subtitle;

  /// Shown before the title in the monospaced face: a username, a project
  /// slug, a key prefix.
  final String? identifier;

  final IconData? icon;

  /// Status and role markers, drawn between the text and the actions.
  final List<Widget> tags;

  /// Buttons, in the order the artboards put them: the safe ones first, the
  /// destructive one last.
  final List<Widget> actions;

  /// Opens the resource. A row with no callback is not interactive — the log
  /// feed's rows are, a key's row is not.
  final VoidCallback? onPressed;

  final bool selected;

  const AdminResourceRow({
    super.key,
    required this.title,
    this.subtitle,
    this.identifier,
    this.icon,
    this.tags = const [],
    this.actions = const [],
    this.onPressed,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);

    return HoverButton(
      onPressed: onPressed,
      builder: (context, states) {
        final background = selected
            ? colors.accentTint
            : (onPressed != null && states.isHovered
                ? colors.cardBg
                : Colors.transparent);
        return Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AdminSpacing.x14,
            vertical: AdminSpacing.x10,
          ),
          decoration: BoxDecoration(
            color: background,
            border: Border(bottom: BorderSide(color: colors.border)),
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: colors.textSecondary),
                const SizedBox(width: AdminSpacing.x10),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (identifier != null) ...[
                          Text(
                            identifier!,
                            style: AdminTypography.monoSmall.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                          const SizedBox(width: AdminSpacing.x8),
                        ],
                        Flexible(
                          child: Text(
                            title,
                            overflow: TextOverflow.ellipsis,
                            style: AdminTypography.body.copyWith(
                              color: colors.text,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: AdminSpacing.x2),
                      Text(
                        subtitle!,
                        overflow: TextOverflow.ellipsis,
                        style: AdminTypography.caption.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              for (final tag in tags) ...[
                const SizedBox(width: AdminSpacing.x8),
                tag,
              ],
              for (final action in actions) ...[
                const SizedBox(width: AdminSpacing.x8),
                action,
              ],
            ],
          ),
        );
      },
    );
  }
}
