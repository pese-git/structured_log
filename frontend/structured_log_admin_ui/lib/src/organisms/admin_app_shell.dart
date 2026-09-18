import 'package:fluent_ui/fluent_ui.dart';

import '../molecules/admin_account_menu.dart';
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

  /// The account block opens a menu (`AccountMenu.dc.html`) rather than
  /// acting on a single tap — "Настройки аккаунта" and "Выйти" are two
  /// distinct actions, not one. Either callback left `null` drops that
  /// item from the menu; both `null` makes the block inert, same as the
  /// old `onAccountPressed: null`.
  final VoidCallback? onOpenAccountSettings;
  final VoidCallback? onSignOut;

  /// The account menu's two rows. English by default like every label in this
  /// kit; the screen passes its own.
  final String accountSettingsLabel;
  final String signOutLabel;

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
    this.onOpenAccountSettings,
    this.onSignOut,
    this.accountSettingsLabel = 'Account settings',
    this.signOutLabel = 'Sign out',
  });

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);
    return LayoutBuilder(
      builder: (context, constraints) {
        // Its own width, not the window's. A shell inside a pane is as wide
        // as the pane, and asking `MediaQuery` would give it the wrong answer
        // in exactly that case (`AdminBreakpoints`).
        final collapsed = constraints.maxWidth < AdminBreakpoints.navRail;
        return _build(colors, collapsed: collapsed);
      },
    );
  }

  Widget _build(AdminColors colors, {required bool collapsed}) {
    return ColoredBox(
      color: colors.pageBg,
      child: Padding(
        padding: const EdgeInsets.all(AdminSpacing.x8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: collapsed
                  ? AdminBreakpoints.navRailWidth
                  : AdminSizes.navPaneWidth,
              child: _NavPane(
                collapsed: collapsed,
                sections: sections,
                selectedIndex: selectedIndex,
                onSelected: onSelected,
                productName: productName,
                accountName: accountName,
                accountRole: accountRole,
                onOpenAccountSettings: onOpenAccountSettings,
                onSignOut: onSignOut,
                accountSettingsLabel: accountSettingsLabel,
                signOutLabel: signOutLabel,
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
  /// Icons only: no labels, no section titles, no account name. Everything
  /// that survives is still reachable — the items keep their tooltips, and
  /// the account block is still the button it was.
  final bool collapsed;

  final List<AdminNavSection> sections;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final String productName;
  final String accountName;
  final String accountRole;
  final VoidCallback? onOpenAccountSettings;
  final VoidCallback? onSignOut;

  /// The account menu's two rows. English by default like every label in this
  /// kit; the screen passes its own.
  final String accountSettingsLabel;
  final String signOutLabel;

  const _NavPane({
    required this.collapsed,
    required this.sections,
    required this.selectedIndex,
    required this.onSelected,
    required this.productName,
    required this.accountName,
    required this.accountRole,
    this.onOpenAccountSettings,
    this.onSignOut,
    this.accountSettingsLabel = 'Account settings',
    this.signOutLabel = 'Sign out',
  });

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);
    var flatIndex = 0;
    final children = <Widget>[];

    for (final section in sections) {
      if (!collapsed) {
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
      }
      for (final item in section.items) {
        final index = flatIndex++;
        children.add(
          Padding(
            padding: EdgeInsets.fromLTRB(
              AdminSpacing.x8,
              0,
              AdminSpacing.x8,
              collapsed ? AdminSpacing.x4 : 0,
            ),
            child: _NavItemView(
              item: item,
              collapsed: collapsed,
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
          padding: EdgeInsets.fromLTRB(
            collapsed ? AdminSpacing.x8 : AdminSpacing.x14,
            AdminSpacing.x12,
            collapsed ? AdminSpacing.x8 : AdminSpacing.x14,
            AdminSpacing.x10,
          ),
          child: Row(
            mainAxisAlignment:
                collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              Icon(FluentIcons.text_document, size: 20, color: colors.accent),
              if (!collapsed) ...[
                const SizedBox(width: AdminSpacing.x10),
                Expanded(
                  child: Text(
                    productName,
                    overflow: TextOverflow.ellipsis,
                    style: AdminTypography.label.copyWith(color: colors.text),
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(child: ListView(children: children)),
        _AccountBlock(
          collapsed: collapsed,
          accountName: accountName,
          accountRole: accountRole,
          onOpenAccountSettings: onOpenAccountSettings,
          onSignOut: onSignOut,
          accountSettingsLabel: accountSettingsLabel,
          signOutLabel: signOutLabel,
        ),
      ],
    );
  }
}

/// The account block at the foot of the nav pane — its own
/// [FlyoutController], so the menu it opens (`AdminAccountMenu`) survives
/// `AdminAppShell` rebuilding around it (every nav selection does).
class _AccountBlock extends StatefulWidget {
  final bool collapsed;
  final String accountName;
  final String accountRole;
  final VoidCallback? onOpenAccountSettings;
  final VoidCallback? onSignOut;

  /// The account menu's two rows. English by default like every label in this
  /// kit; the screen passes its own.
  final String accountSettingsLabel;
  final String signOutLabel;

  const _AccountBlock({
    required this.collapsed,
    required this.accountName,
    required this.accountRole,
    this.onOpenAccountSettings,
    this.onSignOut,
    this.accountSettingsLabel = 'Account settings',
    this.signOutLabel = 'Sign out',
  });

  @override
  State<_AccountBlock> createState() => _AccountBlockState();
}

class _AccountBlockState extends State<_AccountBlock> {
  final _controller = FlyoutController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    await _controller.showFlyout<void>(
      placementMode: FlyoutPlacementMode.topLeft,
      builder: (flyoutContext) => AdminAccountMenu(
        accountName: widget.accountName,
        accountRole: widget.accountRole,
        onOpenAccountSettings: () {
          Navigator.of(flyoutContext).pop();
          widget.onOpenAccountSettings?.call();
        },
        onSignOut: () {
          Navigator.of(flyoutContext).pop();
          widget.onSignOut?.call();
        },
        accountSettingsLabel: widget.accountSettingsLabel,
        signOutLabel: widget.signOutLabel,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AdminColors.of(FluentTheme.of(context).brightness);
    final interactive =
        widget.onOpenAccountSettings != null || widget.onSignOut != null;
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: FlyoutTarget(
        controller: _controller,
        child: HoverButton(
          onPressed: interactive ? _open : null,
          builder: (context, states) => Container(
            padding: EdgeInsets.symmetric(
              horizontal: widget.collapsed ? AdminSpacing.x8 : AdminSpacing.x14,
              vertical: AdminSpacing.x12,
            ),
            color: states.isHovered ? colors.cardBg : null,
            child: Row(
              mainAxisAlignment: widget.collapsed
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
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
                    _initials(widget.accountName),
                    style: AdminTypography.captionStrong.copyWith(
                      color: colors.accentDark,
                    ),
                  ),
                ),
                if (!widget.collapsed) ...[
                  const SizedBox(width: AdminSpacing.x10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.accountName,
                          overflow: TextOverflow.ellipsis,
                          style: AdminTypography.bodySmall.copyWith(
                            color: colors.text,
                          ),
                        ),
                        Text(
                          widget.accountRole,
                          overflow: TextOverflow.ellipsis,
                          style: AdminTypography.caption.copyWith(
                            color: colors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (interactive)
                    Icon(
                      FluentIcons.chevron_down,
                      size: 14,
                      color: colors.textSecondary,
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
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
  final bool collapsed;
  final bool selected;
  final VoidCallback onPressed;

  const _NavItemView({
    required this.item,
    required this.collapsed,
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
              padding: EdgeInsets.symmetric(
                horizontal: collapsed ? 0 : AdminSpacing.x12,
              ),
              decoration: BoxDecoration(
                color: selected
                    ? colors.accentTint
                    : (states.isHovered ? colors.cardBg : null),
                borderRadius: BorderRadius.circular(AdminRadius.control),
              ),
              child: Row(
                mainAxisAlignment: collapsed
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                children: [
                  Icon(
                    item.icon,
                    size: 16,
                    color: selected ? colors.text : colors.textSecondary,
                  ),
                  // The label is what the rail drops, and the tooltip is what
                  // replaces it — an icon alone does not say where it goes.
                  if (!collapsed) ...[
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
