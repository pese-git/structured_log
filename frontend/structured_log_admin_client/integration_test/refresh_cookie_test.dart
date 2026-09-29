import 'package:cherrypick/cherrypick.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:structured_log_admin_client/app/app.dart';
import 'package:structured_log_admin_client/shared/api/token_response.dart';
import 'package:structured_log_admin_client/shared/auth/session_lock.dart';
import 'package:structured_log_admin_client/shared/auth/session_store.dart';
import 'package:structured_log_admin_client/shared/auth/session_controller.dart';
import 'package:structured_log_admin_client/shared/auth/token_storage.dart';
import 'package:structured_log_admin_client/shared/config/app_config.dart';
import 'package:structured_log_admin_client/shared/di/app_module.dart';
import 'package:structured_log_admin_client/shared/l10n/locale_controller.dart';
import 'package:structured_log_admin_client/shared/logging/setup.dart';
import 'package:structured_log_admin_client/testing/mock_server.dart';
import 'package:web/web.dart' as web;

/// Where the session's two halves end up, in a browser.
///
/// This is the one claim of `add-refresh-token-cookie` that no test on the
/// Dart VM can make. `flutter test` and `packages/e2e` run where nothing
/// holds cookies, so `sessionFrom` rightly keeps the copy the body carried —
/// which means the property "the refresh token is out of reach of script on
/// this origin" is only ever true, and only ever observable, here.
///
/// Three things are real in this run and in no other: `kIsWeb`, so the client
/// takes the browser branch; `window.sessionStorage` and `window.localStorage`,
/// so what the app stored can be read back the way an attacker's script would
/// read it; and `navigator.locks`, so the renewal actually goes through the
/// Web Locks implementation rather than its no-op stand-in.
///
/// What is **not** real here is the cookie itself. The network is mocked at
/// `HttpClientAdapter`, below dio, so no `Set-Cookie` header ever reaches the
/// browser and no `Cookie` is ever sent by it. What a browser does with the
/// header is `packages/e2e`'s server-side evidence plus the browser's own
/// documented behaviour; what this file proves is the half that is this
/// application's doing — that having been told a cookie was set, the client
/// keeps nothing readable behind.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const password = 'chosen-by-the-operator';

  /// Every key the page can see in both browser stores.
  ///
  /// Keys, not values, and the distinction is why this file was worth running
  /// rather than reasoning about. `flutter_secure_storage` on the web stores
  /// AES-GCM ciphertext, so a scan for the token's plaintext finds nothing
  /// *whether or not the token is there* — the first version of this test
  /// asserted exactly that, and passed for no reason at all. A key is what
  /// says something is stored under it.
  List<String> storedKeys() {
    final keys = <String>[];
    for (final store in [web.window.localStorage, web.window.sessionStorage]) {
      for (var i = 0; i < store.length; i++) {
        final key = store.key(i);
        if (key != null) keys.add(key);
      }
    }
    return keys;
  }

  void clearBrowserStorage() {
    web.window.localStorage.clear();
    web.window.sessionStorage.clear();
  }

  Future<void> openApp(
    WidgetTester tester,
    MockServer server, {
    required TokenStorage storage,
  }) async {
    await binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => binding.setSurfaceSize(null));

    final session = SessionController();
    final scope = openAppScope(
      config: const AppConfig(baseUrl: 'https://logs.example.test'),
      logger: configureClientLogging(),
      tokenStorage: storage,
      httpAdapter: server,
      onSessionExpired: session.expire,
      onPasswordChangeRequired: session.passwordChangeRequired,
    );
    await tester.pumpWidget(
      AdminApp(
        scope: scope,
        session: session,
        localeController: LocaleController(initial: const Locale('ru')),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The storage the shipped app builds — the browser's own, not a fake.
  TokenStorage realStorage() => SplitTokenStorage(
    accessStore: createSessionStore(),
    refreshStore: const PlatformSecretStore(FlutterSecureStorage()),
  );

  Future<void> signIn(WidgetTester tester) async {
    final fields = find.byType(TextBox);
    await tester.tap(fields.first);
    await tester.pumpAndSettle();
    await tester.enterText(fields.first, 'admin');
    await tester.pumpAndSettle();
    await tester.tap(fields.last);
    await tester.pumpAndSettle();
    await tester.enterText(fields.last, password);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Войти'));
    await tester.pumpAndSettle();
  }

  setUp(clearBrowserStorage);
  tearDown(() {
    CherryPick.closeRootScope();
    clearBrowserStorage();
  });

  testWidgets('the client runs the browser branch at all', (tester) async {
    // If this is false the two tests below would pass for the wrong reason:
    // the client would be keeping its copy because it thinks it is on a VM,
    // and "nothing reachable" would be a statement about an empty app.
    expect(platformHoldsCookies, isTrue);
    expect(createSessionLock(), isNot(isA<NoSessionLock>()));
    expect(createSessionStore(), isNot(isA<InMemorySessionStore>()));
  });

  testWidgets('with the cookie, nothing readable holds the refresh token', (
    tester,
  ) async {
    final server = MockServer(username: 'admin', password: password)
      ..refreshTokenCookie = true;
    final storage = realStorage();
    await openApp(tester, server, storage: storage);

    await signIn(tester);

    expect(find.text('Вход в систему'), findsNothing);
    expect(
      await storage.readRefreshToken(),
      isNull,
      reason: 'the client was told a cookie was set and let go of its copy',
    );
    expect(
      storedKeys().any((k) => k.contains('refresh_token')),
      isFalse,
      reason:
          'and nothing is stored under that name either — the assertion '
          'above goes through the app, this one goes around it',
    );
    expect(
      web.window.sessionStorage.getItem('structured_log.access_token'),
      isNotNull,
      reason:
          'the access token is meant to be here, in plain sight: it is sent '
          'as a header on every request, so the page has to read it. Fifteen '
          'minutes, and it dies with the tab',
    );
    expect(
      web.window.localStorage.getItem('structured_log.access_token'),
      isNull,
      reason:
          'per tab, not shared — a second tab renews rather than borrowing '
          'this one',
    );
  });

  testWidgets('without the cookie, the client holds it — as it must', (
    tester,
  ) async {
    // The contrast, spelled out rather than implied. A deployment serving the
    // client from an origin the operator declared foreign gets no cookie, and
    // there the token has nowhere else to live. This is what the change
    // improves on, not a regression.
    final server = MockServer(username: 'admin', password: password)
      ..refreshTokenCookie = false;
    final storage = realStorage();
    await openApp(tester, server, storage: storage);

    await signIn(tester);

    expect(find.text('Вход в систему'), findsNothing);
    expect(
      await storage.readRefreshToken(),
      isNotNull,
      reason:
          'no cookie in this deployment — the session could not be renewed '
          'at all if the client let go of it',
    );
    expect(storedKeys().any((k) => k.contains('refresh_token')), isTrue);
    expect(
      storedKeys(),
      contains('FlutterSecureStorage'),
      reason:
          'and this is the whole argument for the change, observed rather '
          'than taken from documentation: the key that decrypts the token is '
          'in the same store as the token, readable by any script on this '
          'origin. "Secure storage" on the web is obfuscation',
    );
  });

  testWidgets('a renewal completes through the real Web Lock', (tester) async {
    // `_WebSessionLock` converts a Dart future to a JS promise and back, and
    // nothing on the VM exercises that: `NoSessionLock` runs the body
    // directly. A mistake in the conversion does not throw — it never
    // settles, so the renewal hangs and the app sits on a spinner forever.
    // The assertion is simply that the screen after the renewal arrives.
    final server = MockServer(username: 'admin', password: password)
      ..refreshTokenCookie = true;
    final storage = realStorage();
    await openApp(tester, server, storage: storage);
    await signIn(tester);

    // Every access token issued so far stops being accepted, so the next
    // request 401s and the interceptor renews — inside the lock.
    server.expireAccessTokens();

    await tester.tap(find.text('Группы').first);
    await tester.pumpAndSettle(const Duration(seconds: 5));

    expect(
      find.text('Вход в систему'),
      findsNothing,
      reason:
          'a renewal that never settled would end at the login screen, or '
          'never leave the spinner',
    );
    expect(
      storedKeys().any((k) => k.contains('refresh_token')),
      isFalse,
      reason: 'the renewed session is held the same way the first one was',
    );
  });
}
