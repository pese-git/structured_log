import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log_admin_client/features/users/presentation/sole_owner_conflict_dialog.dart';
import 'package:structured_log_admin_client/features/users/presentation/user_dialogs.dart';
import 'package:structured_log_admin_client/features/users/presentation/user_failure_text.dart';
import 'package:structured_log_admin_client/l10n/app_localizations.dart';
import 'package:structured_log_admin_client/shared/api/api_failure.dart';

import '../../support/localized_app.dart';

void main() {
  testWidgets('the create dialog reads in English', (tester) async {
    await tester.pumpWidget(
      localizedApp(
        locale: const Locale('en'),
        home: ScaffoldPage(
          content: CreateUserDialog(onCreate: (_, _, _) {}, onCancel: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('New user'), findsOneWidget);
    expect(find.text('Temporary password'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Новый пользователь'), findsNothing);
  });

  testWidgets('the sole-owner dialog reads in English', (tester) async {
    await tester.pumpWidget(
      localizedApp(
        locale: const Locale('en'),
        home: ScaffoldPage(
          content: SoleOwnerConflictDialog(
            groups: const [(id: 1, name: 'Ops')],
            onGrantAccess: (_) {},
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Transfer ownership first'), findsOneWidget);
    expect(find.text('Grant role'), findsOneWidget);
    expect(find.text('Got it'), findsOneWidget);
    expect(find.text('Понятно'), findsNothing);
  });

  testWidgets('the dialog speaks of "you" only for one\'s own account', (
    tester,
  ) async {
    Future<void> pump({required bool own}) async {
      await tester.pumpWidget(
        localizedApp(
          locale: const Locale('en'),
          home: ScaffoldPage(
            content: SoleOwnerConflictDialog(
              ownAccount: own,
              groups: const [(id: 1, name: 'Ops')],
              onClose: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pump(own: false);
    expect(find.textContaining('The user is the only owner'), findsOneWidget);
    expect(find.textContaining('You are the only owner'), findsNothing);

    await pump(own: true);
    expect(find.textContaining('You are the only owner'), findsOneWidget);
    expect(find.textContaining('The user is the only owner'), findsNothing);
  });

  test('failure text follows the locale', () {
    const failure = ApiFailure.rateLimited(retryAfter: Duration(seconds: 7));
    expect(
      describeUserFailure(lookupAppLocalizations(const Locale('en')), failure),
      'Too many attempts. Try again in 7 s.',
    );
    expect(
      describeUserFailure(lookupAppLocalizations(const Locale('ru')), failure),
      'Слишком много попыток. Попробуйте через 7 с.',
    );
  });
}
