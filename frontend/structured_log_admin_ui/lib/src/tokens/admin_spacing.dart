/// The spacing and shape values the canvas uses.
///
/// Named by their measurement rather than by a role invented here: every one
/// of these is a literal that appears in the artboards, so a widget written
/// against the mockup can cite the same number it reads there. Semantic names
/// would need a second, unverifiable mapping in between.
abstract final class AdminSpacing {
  static const double x2 = 2;
  static const double x4 = 4;
  static const double x6 = 6;
  static const double x8 = 8;
  static const double x10 = 10;
  static const double x12 = 12;
  static const double x14 = 14;
  static const double x18 = 18;
  static const double x24 = 24;
  static const double x28 = 28;
}

/// Corner radii, from the canvas.
abstract final class AdminRadius {
  /// The active nav item's left rail.
  static const double rail = 2;

  /// Buttons, inputs, tags, badges — every control.
  static const double control = 4;

  /// Cards and the content pane.
  static const double card = 8;

  /// Fully rounded: the live pill and the avatar.
  static const double pill = 999;
}

/// Control heights, from the canvas.
///
/// Fluent sizes controls by role rather than on one scale, and the mockups
/// follow that: a filter box is taller than the button beside it.
abstract final class AdminSizes {
  /// Level badge, tag chip.
  static const double badgeHeight = 22;

  /// The live-status pill in the log feed.
  static const double pillHeight = 26;

  /// A tonal button inside a card.
  static const double tonalButtonHeight = 28;

  /// Accent and standard buttons in a toolbar.
  static const double buttonHeight = 30;

  /// Filter boxes, inputs, the avatar.
  static const double controlHeight = 32;

  /// A navigation item.
  static const double navItemHeight = 40;

  /// The navigation pane when it shows labels.
  static const double navPaneWidth = 252;

  /// The master list in a master/detail screen.
  static const double masterListWidth = 340;

  /// The level badge's fixed width, so a column of them aligns.
  static const double levelBadgeWidth = 34;
}
