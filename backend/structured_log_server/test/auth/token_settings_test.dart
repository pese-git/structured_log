import 'dart:convert';

import 'package:structured_log_server/src/auth/token_settings.dart';
import 'package:test/test.dart';

void main() {
  group('jwtSecretPolicyMessage', () {
    test('accepts a secret at the minimum', () {
      expect(jwtSecretPolicyMessage('x' * minJwtSecretBytes), isNull);
    });

    test('accepts a longer one', () {
      expect(jwtSecretPolicyMessage('x' * (minJwtSecretBytes + 100)), isNull);
    });

    test('accepts what the deployment scripts generate', () {
      // `openssl rand -base64 48 | tr -d '\n'` — 64 characters, which is what
      // `deploy/deploy.sh` and `deploy/k8s/create-secrets.sh` both write. A
      // rule that refused its own tooling's output would be a rule nobody
      // could satisfy by following the documentation.
      expect(jwtSecretPolicyMessage('A' * 64), isNull);
    });

    test('refuses one byte short of the minimum', () {
      final message = jwtSecretPolicyMessage('x' * (minJwtSecretBytes - 1));
      expect(message, isNotNull);
      expect(message, contains('$minJwtSecretBytes'));
    });

    test('refuses an empty secret', () {
      expect(jwtSecretPolicyMessage(''), isNotNull);
    });

    test('counts bytes, not characters', () {
      // Sixteen Cyrillic letters are sixteen characters and thirty-two bytes.
      // The rule is about how much key the HMAC gets, which is bytes.
      final cyrillic = 'ж' * (minJwtSecretBytes ~/ 2);
      expect(cyrillic.runes.length, minJwtSecretBytes ~/ 2);
      expect(utf8.encode(cyrillic).length, minJwtSecretBytes);
      expect(
        jwtSecretPolicyMessage(cyrillic),
        isNull,
        reason: 'long enough in bytes, though half that in characters',
      );
    });

    test('never repeats the secret back', () {
      const secret = 'hunter2';
      final message = jwtSecretPolicyMessage(secret);
      expect(message, isNotNull);
      expect(
        message,
        isNot(contains(secret)),
        reason:
            'this sentence is printed to the console and may reach a log or a '
            'ticket; the secret it is complaining about must not travel with '
            'it',
      );
    });
  });
}
