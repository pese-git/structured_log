import 'package:cherrypick/cherrypick.dart';
// fluent_ui, not flutter/widgets: the latter re-exports dart:ui's TextBox — a
// text geometry rectangle, not a widget — and `find.byType(TextBox)` would
// then compile and match nothing at all.
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log_admin_client/app/app.dart';
import 'package:structured_log_admin_client/shared/auth/session_controller.dart';
import 'package:structured_log_admin_client/shared/auth/token_pair.dart';
import 'package:structured_log_admin_client/shared/auth/token_storage.dart';
import 'package:structured_log_admin_client/shared/config/app_config.dart';
import 'package:structured_log_admin_client/shared/di/app_module.dart';
import 'package:structured_log_admin_client/shared/logging/setup.dart';

import 'package:structured_log_admin_client/testing/mock_server.dart';

/// Where the mock deployment lives. Only its authority is ever shown, on the
/// login screen.
const testBaseUrl = 'https://logs.example.test';

/// The whole application over a [MockServer], composed exactly the way
/// `main()` composes it — scope, session controller, both interceptor
/// callbacks — so what these tests exercise is the wiring and not a screen
/// held up by hand.
class AppHarness {
  final MockServer server;
  final SessionController session;
  final InMemoryTokenStorage storage;
  final Scope scope;

  const AppHarness._({
    required this.server,
    required this.session,
    required this.storage,
    required this.scope,
  });

  /// The name shown once the shell is up, read out of the access token.
  String get accountName => server.username;
}

/// Builds and pumps the app.
///
/// Pass [signedIn] to start behind the login screen with a session the mock
/// server will honour — most flows are about what happens afterwards, and
/// typing credentials first would only make them longer.
///
/// Pass [storage] to keep a session across several `testWidgets` in one file.
/// A flow written as ordered steps opens the app again at each of them, which
/// is what coming back to it looks like, and the session survives between them
/// for the same reason a real one would: the store outlives the window.
Future<AppHarness> pumpApp(
  WidgetTester tester,
  MockServer server, {
  bool signedIn = false,
  InMemoryTokenStorage? storage,
  Size surface = const Size(1440, 900),
}) async {
  // The screens are laid out against artboards 1160–1440 wide. At the default
  // 800 the shell shows a rail instead of a labelled nav pane, the log screen
  // stops being a master-detail split, and a tap on a control that ended up
  // off-screen warns and does nothing rather than failing outright.
  tester.view.physicalSize = surface;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final tokens = storage ?? InMemoryTokenStorage();
  if (signedIn) {
    final issued = server.issueSession();
    await tokens.write(
      TokenPair(
        accessToken: issued.accessToken,
        refreshToken: issued.refreshToken,
      ),
    );
  }

  final session = SessionController();
  final scope = openAppScope(
    config: const AppConfig(baseUrl: testBaseUrl),
    logger: configureClientLogging(),
    tokenStorage: tokens,
    httpAdapter: server,
    onSessionExpired: session.expire,
    onPasswordChangeRequired: session.passwordChangeRequired,
  );

  await tester.pumpWidget(AdminApp(scope: scope, session: session));
  await tester.pumpAndSettle();

  return AppHarness._(
    server: server,
    session: session,
    storage: tokens,
    scope: scope,
  );
}

/// Signs in through the login screen.
Future<void> signIn(
  WidgetTester tester, {
  String username = 'root',
  String password = 'correct',
}) async {
  await tester.enterText(find.byType(TextBox).first, username);
  await tester.enterText(find.byType(TextBox).last, password);
  await tester.tap(find.text('Войти'));
  await tester.pumpAndSettle();
}

/// Unmounts the app, inside the test, so everything it owns is disposed while
/// the tester can still run the frames that finish the job.
///
/// Not optional for anything that opened the log feed. The live subscription
/// is a real `dio` request against a body that stays open, and it is the
/// bloc's `close()` — reached through `BlocProvider`'s dispose — that cancels
/// it; a feed left mounted leaves the reconnect backoff holding a timer, and
/// `testWidgets` fails the test for it rather than ignoring it.
Future<void> closeApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

/// Moves the shell to the log section. The nav item's label, as `HomeShell`
/// spells it.
Future<void> openLogs(WidgetTester tester) async {
  await tester.tap(find.text('Поиск логов'));
  await tester.pumpAndSettle();
}
