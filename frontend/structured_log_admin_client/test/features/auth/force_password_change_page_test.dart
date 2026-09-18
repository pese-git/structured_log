import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:structured_log_admin_client/shared/l10n/locale_controller.dart';
import 'package:structured_log_admin_client/features/auth/application/change_password.dart';
import 'package:structured_log_admin_client/features/auth/domain/auth_failure.dart';
import 'package:structured_log_admin_client/features/auth/domain/auth_repository.dart';
import 'package:structured_log_admin_client/features/auth/presentation/change_password_cubit.dart';
import 'package:structured_log_admin_client/features/auth/presentation/force_password_change_page.dart';

import '../../support/localized_app.dart';

class _FakeRepository implements AuthRepository {
  Either<AuthFailure, Unit> answer = right(unit);

  @override
  Future<Either<AuthFailure, Unit>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async => answer;

  @override
  Future<String?> currentUsername() async => 'admin';

  @override
  Future<bool> isGlobalAdmin() async => false;

  @override
  Future<Either<AuthFailure, Unit>> signIn({
    required String username,
    required String password,
  }) async => right(unit);

  @override
  Future<void> signOut() async {}

  @override
  Future<bool> hasSession() async => true;
}

void main() {
  late _FakeRepository repository;
  late int changed;
  late int signedOut;

  setUp(() {
    repository = _FakeRepository();
    changed = 0;
    signedOut = 0;
  });

  Future<void> pump(WidgetTester tester, {Locale? locale}) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      localizedApp(
        locale: locale ?? const Locale('ru'),
        home: BlocProvider(
          create: (_) => ChangePasswordCubit(
            changePassword: ChangePassword(repository),
            currentUsername: CurrentUsername(repository),
          ),
          child: ForcePasswordChangePage(
            onChanged: () => changed++,
            onSignOut: () => signedOut++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> fill(
    WidgetTester tester, {
    String current = 'temporary',
    String next = 'chosen',
    String? repeat,
  }) async {
    final fields = find.byType(TextBox);
    await tester.enterText(fields.at(0), current);
    await tester.enterText(fields.at(1), next);
    await tester.enterText(fields.at(2), repeat ?? next);
    await tester.tap(find.text('Сменить пароль и продолжить'));
    await tester.pumpAndSettle();
  }

  testWidgets('the corner switcher changes the language of the gate too', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = LocaleController(initial: const Locale('ru'));

    await tester.pumpWidget(
      ListenableBuilder(
        listenable: controller,
        builder: (_, _) => localizedApp(
          locale: controller.locale!,
          home: BlocProvider(
            create: (_) => ChangePasswordCubit(
              changePassword: ChangePassword(repository),
              currentUsername: CurrentUsername(repository),
            ),
            child: ForcePasswordChangePage(
              onChanged: () {},
              onSignOut: () {},
              localeController: controller,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Смените пароль'), findsOneWidget);

    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    expect(find.text('Change your password'), findsOneWidget);
    expect(find.text('Смените пароль'), findsNothing);
  });

  testWidgets('it says why the rest of the app is closed', (tester) async {
    await pump(tester);

    expect(find.text('Смените пароль'), findsOneWidget);
    expect(find.textContaining('временным'), findsWidgets);
    expect(
      find.textContaining('Вошли как admin'),
      findsOneWidget,
      reason:
          'the name comes out of the access token — there is no '
          'GET /v1/users/me in this stage',
    );
  });

  testWidgets('a successful change offers the way in', (tester) async {
    await pump(tester);

    await fill(tester);

    expect(find.text('Пароль изменён'), findsOneWidget);
    expect(changed, 0, reason: 'the reader confirms before the app takes over');

    await tester.tap(find.text('Перейти в приложение'));
    await tester.pumpAndSettle();
    expect(changed, 1);
  });

  testWidgets('a wrong current password does not open the app', (tester) async {
    repository.answer = left(const AuthFailure.invalidCredentials());
    await pump(tester);

    await fill(tester);

    expect(find.textContaining('Текущий пароль неверен'), findsOneWidget);
    expect(find.text('Смените пароль'), findsOneWidget);
    expect(changed, 0);
  });

  testWidgets('two different new passwords are caught before sending', (
    tester,
  ) async {
    await pump(tester);

    await fill(tester, repeat: 'chsoen');

    expect(find.text('Пароли не совпадают'), findsOneWidget);
    expect(find.text('Пароль изменён'), findsNothing);
  });

  testWidgets('signing out is the only other way off the screen', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(find.text('Выйти'));
    await tester.pumpAndSettle();

    expect(signedOut, 1);
  });

  testWidgets('renders in English when the locale is English', (tester) async {
    await pump(tester, locale: const Locale('en'));

    expect(find.text('Change your password'), findsOneWidget);
    expect(find.text('Change password and continue'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
    expect(find.text('Смените пароль'), findsNothing);
    expect(find.text('Выйти'), findsNothing);
  });
}
