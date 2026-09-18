import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The two ARB files are edited by hand, and `gen-l10n` does not fail on a
/// message missing from a translation — the generated Russian class quietly
/// falls back to English. This is what makes a forgotten Russian string a red
/// test rather than an English word in a Russian screen.
Map<String, dynamic> _arb(String locale) =>
    jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
        as Map<String, dynamic>;

Set<String> _messages(Map<String, dynamic> arb) =>
    arb.keys.where((k) => !k.startsWith('@')).toSet();

void main() {
  final en = _arb('en');
  final ru = _arb('ru');

  test('every English message has a Russian one, and the other way round', () {
    expect(_messages(ru).difference(_messages(en)), isEmpty, reason: 'only ru');
    expect(_messages(en).difference(_messages(ru)), isEmpty, reason: 'only en');
  });

  test('a translation uses the placeholders its template declares', () {
    final placeholder = RegExp(r'\{(\w+)[,}]');
    for (final key in _messages(en)) {
      final declared =
          ((en['@$key'] as Map<String, dynamic>?)?['placeholders']
                  as Map<String, dynamic>?)
              ?.keys
              .toSet() ??
          <String>{};
      final used = placeholder
          .allMatches(ru[key] as String)
          .map((m) => m.group(1)!)
          .toSet();
      expect(
        used.difference(declared),
        isEmpty,
        reason: '$key: Russian uses a placeholder English does not declare',
      );
    }
  });

  test('no message is left empty', () {
    for (final key in _messages(en)) {
      // `monthShort`'s `other{}` is the one deliberately empty branch, inside
      // a non-empty message.
      expect((en[key] as String).trim(), isNotEmpty, reason: 'en $key');
      expect((ru[key] as String).trim(), isNotEmpty, reason: 'ru $key');
    }
  });
}
