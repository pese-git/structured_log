import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log_admin_client/l10n/app_localizations_en.dart';
import 'package:structured_log_admin_client/l10n/app_localizations_ru.dart';
import 'package:structured_log_admin_client/shared/auth/password_rejection.dart';

void main() {
  final en = AppLocalizationsEn();
  final ru = AppLocalizationsRu();

  group('describePasswordRejection', () {
    test('too_short names the minimum the server gave', () {
      const details = {
        'field': 'password',
        'reason': 'too_short',
        'min_length': 10,
      };
      expect(
        describePasswordRejection(en, details),
        'The password must be at least 10 characters.',
      );
      expect(
        describePasswordRejection(ru, details),
        'Пароль должен быть не короче 10 символов.',
      );
    });

    test('too_long names the limit and warns that Cyrillic counts double', () {
      const details = {'reason': 'too_long', 'max_bytes': 72};
      expect(describePasswordRejection(en, details), contains('72 bytes'));
      expect(describePasswordRejection(ru, details), contains('72 байт'));
    });

    test('a response without the number falls back to the known default', () {
      expect(
        describePasswordRejection(en, const {'reason': 'too_short'}),
        contains('at least 8'),
      );
      expect(
        describePasswordRejection(en, const {'reason': 'too_long'}),
        contains('72'),
      );
    });

    test('anything that is not a password refusal is null', () {
      expect(describePasswordRejection(en, null), isNull);
      expect(describePasswordRejection(en, const {}), isNull);
      expect(
        describePasswordRejection(en, const {'reason': 'required'}),
        isNull,
      );
    });
  });

  group('isPasswordRejection', () {
    test('recognises the two reasons and nothing else', () {
      expect(isPasswordRejection(const {'reason': 'too_short'}), isTrue);
      expect(isPasswordRejection(const {'reason': 'too_long'}), isTrue);
      expect(isPasswordRejection(const {'reason': 'invalid'}), isFalse);
      expect(isPasswordRejection(null), isFalse);
    });
  });
}
