import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log_admin_ui/structured_log_admin_ui.dart';

void main() {
  group('level foregrounds match the canvas', () {
    // The four levels the "Structured Log Admin UI" canvas actually draws, as
    // written in LogBrowser.dc.html's entry data. A change here is a change
    // away from the design, not a refactor.
    const canvas = <AdminLogLevel, Color>{
      AdminLogLevel.debug: Color(0xFF06B6D4),
      AdminLogLevel.info: Color(0xFF16A34A),
      AdminLogLevel.warning: Color(0xFFD97706),
      AdminLogLevel.error: Color(0xFFDC2626),
    };

    canvas.forEach((level, expected) {
      test(AdminLogLevelColors.abbreviation(level), () {
        expect(
          AdminLogLevelColors.foreground(level, Brightness.light),
          expected,
        );
      });
    });
  });

  group('badge grounds reproduce the canvas from the tint rule', () {
    // Not a second table: these are what `foreground` laid over the surface at
    // 16% comes out as, and the canvas's own badge grounds. If the rule and
    // the mockup ever disagree, this fails rather than letting `trace` and
    // `critical` — which no artboard draws — quietly drift from the rest.
    const canvas = <AdminLogLevel, Color>{
      AdminLogLevel.debug: Color(0xFFD7F3F8),
      AdminLogLevel.info: Color(0xFFDAF0E2),
      AdminLogLevel.warning: Color(0xFFF9E9D7),
      AdminLogLevel.error: Color(0xFFF9DCDC),
    };

    canvas.forEach((level, expected) {
      test(AdminLogLevelColors.abbreviation(level), () {
        // Compared as 8-bit channels: `Color` keeps floating-point
        // components, so a blend lands a fraction of a step off the hex the
        // canvas is written in, while the colour that actually gets painted
        // is identical.
        expect(
          AdminLogLevelColors.background(level, Brightness.light).toARGB32(),
          expected.toARGB32(),
        );
      });
    });
  });

  test('every level has a three-letter badge', () {
    for (final level in AdminLogLevel.values) {
      expect(AdminLogLevelColors.abbreviation(level), hasLength(3));
    }
  });

  test('levels are ordered by severity', () {
    expect(AdminLogLevel.values, [
      AdminLogLevel.trace,
      AdminLogLevel.debug,
      AdminLogLevel.info,
      AdminLogLevel.warning,
      AdminLogLevel.error,
      AdminLogLevel.critical,
    ]);
  });

  test('foreground and background differ in both themes', () {
    for (final brightness in Brightness.values) {
      for (final level in AdminLogLevel.values) {
        expect(
          AdminLogLevelColors.foreground(level, brightness),
          isNot(AdminLogLevelColors.background(level, brightness)),
        );
      }
    }
  });
}
