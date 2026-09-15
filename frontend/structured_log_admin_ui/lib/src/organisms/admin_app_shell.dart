import 'package:fluent_ui/fluent_ui.dart';

import '../tokens/tokens.dart';

/// One entry in the navigation pane.
///
/// A plain value of primitives — an icon and a label — not a route or a
/// permission. Which entries exist is decided by the caller from the viewer's
/// role: the artboards hide "Пользователи" and "Аудит" from anyone but an
/// administrator rather than disabling them.
@immutable
class AdminNavItem {
  final IconData icon;
  final String label;

  const AdminNavItem({required this.icon, required this.label});
}

/// A titled group of [AdminNavItem]s — "Обзор", "Администрирование", "Логи".
@immutable
class AdminNavSection {
  final String title;
  final List<AdminNavItem> items;

  const AdminNavSection({required this.title, required this.items});
}

/// The frame every screen after sign-in sits in: navigation pane on the left,
/// titled content pane on the right.
///
/// Holds no navigation state. [selectedIndex] counts across every section's
/// items in order, and [onSelected] reports the index that was pressed — the
/// client's router owns what that means.
class AdminAppShell extends StatelessWidget {
  final List<AdminNavSection> sections;

  /// Index into the flattened list of items across all [sections].
  final int selectedIndex;

  final ValueChanged<int> onSelected;

  /// The heading above the content — the artboards repeat the current
  /// section's name here at 28px.
  /// The page heading, drawn at the top of the content pane.
  ///
  /// `null` for a screen that draws its own — which is what the artboards
  /// mostly show, because the primary action sits on the same line as the
  /// heading ("Группы" beside "Создать группу", "Логи" beside the scope
  /// pill) and only the screen knows what that action is. Passing a title
  /// here *and* drawing one prints it twice.
  final String? title;

  final Widget content;

  /// Product name beside the mark at the top of the pane.
  final String productName;

  /// The signed-in account, shown at the foot of the pane.
  final String accountName;
  final String accountRole;

  /// Pressed on the account block — the artboards put sign-out there.
  final VoidCallback? onAccountPressed;

  const AdminAppShell({
    super.key,
    required this.sections,
    required this.selectedIndex,
    required this.onSelected,
    this.title,
    required this.content,
    required this.accountName,
    required this.accountRole,
    this.productName = 'Structured Log',
    this.onAccountPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);
    return ColoredBox(
      color: colors.pageBg,
      child: Padding(
        padding: const EdgeInsets.all(AdminSpacing.x8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: AdminSizes.navPaneWidth,
              child: _NavPane(
                sections: sections,
                selectedIndex: selectedIndex,
                onSelected: onSelected,
                productName: productName,
                accountName: accountName,
                accountRole: accountRole,
                onAccountPressed: onAccountPressed,
              ),
            ),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surface,
                  border: Border.all(color: colors.border),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(AdminRadius.card),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (title != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AdminSpacing.x24,
                          AdminSpacing.x18,
                          AdminSpacing.x24,
                          AdminSpacing.x12,
                        ),
                        child: Text(
                          title!,
                          style: AdminTypography.pageTitle.copyWith(
                            color: colors.text,
                          ),
                        ),
                      ),
                    Expanded(child: content),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavPane extends StatelessWidget {
  final List<AdminNavSection> sections;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final String productName;
  final String accountName;
  final String accountRole;
  final VoidCallback? onAccountPressed;

  const _NavPane({
    required this.sections,
    required this.selectedIndex,
    required this.onSelected,
    required this.productName,
    required this.accountName,
    required this.accountRole,
    this.onAccountPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);
    var flatIndex = 0;
    final children = <Widget>[];

    for (final section in sections) {
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AdminSpacing.x14,
            AdminSpacing.x14,
            AdminSpacing.x14,
            AdminSpacing.x4,
          ),
          child: Text(
            section.title,
            style: AdminTypography.caption.copyWith(
              color: colors.textTertiary,
            ),
          ),
        ),
      );
      for (final item in section.items) {
        final index = flatIndex++;
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AdminSpacing.x8),
            child: _NavItemView(
              item: item,
              selected: index == selectedIndex,
              onPressed: () => onSelected(index),
            ),
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AdminSpacing.x14,
            AdminSpacing.x12,
            AdminSpacing.x14,
            AdminSpacing.x10,
          ),
          child: Row(
            children: [
              Icon(FluentIcons.text_document, size: 20, color: colors.accent),
              const SizedBox(width: AdminSpacing.x10),
              Expanded(
                child: Text(
                  productName,
                  overflow: TextOverflow.ellipsis,
                  style: AdminTypography.label.copyWith(color: colors.text),
                ),
              ),
            ],
          ),
        ),
        Expanded(child: ListView(children: children)),
        Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: colors.border)),
          ),
          child: HoverButton(
            onPressed: onAccountPressed,
            builder: (context, states) => Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AdminSpacing.x14,
                vertical: AdminSpacing.x12,
              ),
              color: states.isHovered ? colors.cardBg : null,
              child: Row(
                children: [
                  Container(
                    width: AdminSizes.controlHeight,
                    height: AdminSizes.controlHeight,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.accentTint,
                      borderRadius: BorderRadius.circular(AdminRadius.pill),
                    ),
                    child: Text(
                      _initials(accountName),
                      style: AdminTypography.captionStrong.copyWith(
                        color: colors.accentDark,
                      ),
                    ),
                  ),
                  const SizedBox(width: AdminSpacing.x10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          accountName,
                          overflow: TextOverflow.ellipsis,
                          style: AdminTypography.bodySmall.copyWith(
                            color: colors.text,
                          ),
                        ),
                        Text(
                          accountRole,
                          overflow: TextOverflow.ellipsis,
                          style: AdminTypography.caption.copyWith(
                            color: colors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (onAccountPressed != null)
                    Icon(
                      FluentIcons.sign_out,
                      size: 16,
                      color: colors.textSecondary,
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Up to two letters, as the artboards show in the avatar.
  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'))
      ..removeWhere((p) => p.isEmpty);
    if (parts.isEmpty) return '';
    if (parts.length == 1) {
      return parts.first.characters.first.toUpperCase();
    }
    return (parts.first.characters.first + parts[1].characters.first)
        .toUpperCase();
  }
}

class _NavItemView extends StatelessWidget {
  final AdminNavItem item;
  final bool selected;
  final VoidCallback onPressed;

  const _NavItemView({
    required this.item,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);
    return HoverButton(
      onPressed: onPressed,
      builder: (context, states) {
        return Stack(
          children: [
            Container(
              height: AdminSizes.navItemHeight,
              padding: const EdgeInsets.symmetric(
                horizontal: AdminSpacing.x12,
              ),
              decoration: BoxDecoration(
                color: selected
                    ? colors.accentTint
                    : (states.isHovered ? colors.cardBg : null),
                borderRadius: BorderRadius.circular(AdminRadius.control),
              ),
              child: Row(
                children: [
                  Icon(
                    item.icon,
                    size: 16,
                    color: selected ? colors.text : colors.textSecondary,
                  ),
                  const SizedBox(width: AdminSpacing.x12),
                  Expanded(
                    child: Text(
                      item.label,
                      overflow: TextOverflow.ellipsis,
                      style: (selected
                              ? AdminTypography.label
                              : AdminTypography.body)
                          .copyWith(
                        color: selected ? colors.text : colors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // The accent rail the canvas hangs off the selected item's left
            // edge, outside its rounded ground.
            if (selected)
              Positioned(
                left: 0,
                top: 9,
                child: Container(
                  width: 3,
                  height: 22,
                  decoration: BoxDecoration(
                    color: colors.accent,
                    borderRadius: BorderRadius.circular(AdminRadius.rail),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
