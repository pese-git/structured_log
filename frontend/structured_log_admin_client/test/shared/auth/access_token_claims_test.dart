import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log_admin_client/shared/auth/access_token_claims.dart';

/// A token shaped like the server's, unsigned — which is all this client ever
/// reads. The signature is never checked and must not be.
String _token(Map<String, dynamic> payload) {
  String segment(Map<String, dynamic> claims) =>
      base64Url.encode(utf8.encode(jsonEncode(claims))).replaceAll('=', '');
  return '${segment({'alg': 'none'})}.${segment(payload)}.not-checked';
}

void main() {
  group('usernameFromAccessToken', () {
    test('the claim is read', () {
      expect(
        usernameFromAccessToken(_token({'preferred_username': 'root'})),
        'root',
      );
    });

    test('a token without the claim yields nothing, not an empty name', () {
      expect(usernameFromAccessToken(_token({'sub': '1'})), isNull);
    });
  });

  group('isGlobalAdminFromAccessToken', () {
    test('admin at global scope', () {
      final token = _token({
        'roles': [
          {'role': 'admin', 'scope_type': 'global', 'scope_id': null},
        ],
      });

      expect(isGlobalAdminFromAccessToken(token), isTrue);
    });

    test('admin of one group is not a global administrator', () {
      // The audit log spans every tenant, so a group-scoped admin has no
      // partial view of it to be offered (`specs/log-server-audit`).
      final token = _token({
        'roles': [
          {'role': 'admin', 'scope_type': 'group', 'scope_id': 1},
        ],
      });

      expect(isGlobalAdminFromAccessToken(token), isFalse);
    });

    test('another role at global scope is not admin', () {
      final token = _token({
        'roles': [
          {'role': 'owner', 'scope_type': 'global', 'scope_id': null},
        ],
      });

      expect(isGlobalAdminFromAccessToken(token), isFalse);
    });

    test('one matching role among several is enough', () {
      final token = _token({
        'roles': [
          {'role': 'user', 'scope_type': 'project', 'scope_id': 3},
          {'role': 'admin', 'scope_type': 'global', 'scope_id': null},
        ],
      });

      expect(isGlobalAdminFromAccessToken(token), isTrue);
    });

    test('no claim, a malformed token and a truncated one all say no', () {
      // Closed rather than open: an unreadable token must not buy a section.
      expect(isGlobalAdminFromAccessToken(_token({'sub': '1'})), isFalse);
      expect(isGlobalAdminFromAccessToken(_token({'roles': 'admin'})), isFalse);
      expect(isGlobalAdminFromAccessToken('not-a-token'), isFalse);
      expect(isGlobalAdminFromAccessToken('a.!!!.c'), isFalse);
    });
  });
}
