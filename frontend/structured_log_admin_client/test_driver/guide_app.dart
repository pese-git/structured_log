import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/semantics.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:structured_log_admin_client/app/app.dart';
import 'package:structured_log_admin_client/shared/auth/session_controller.dart';
import 'package:structured_log_admin_client/shared/auth/token_pair.dart';
import 'package:structured_log_admin_client/shared/auth/token_storage.dart';
import 'package:structured_log_admin_client/shared/config/app_config.dart';
import 'package:structured_log_admin_client/shared/di/app_module.dart';
import 'package:structured_log_admin_client/shared/l10n/locale_controller.dart';
import 'package:structured_log_admin_client/shared/logging/setup.dart';
import 'package:structured_log_admin_client/testing/mock_server.dart';

import 'guide_fixture.dart';

/// The application as the user guide shows it, on the same mocked network as
/// `app.dart` beside this file, driven by `tool/screenshots/shoot.mjs`.
///
/// Its own entry point rather than a flag on `app.dart`: that one is seeded
/// for `user_flow_test.dart` and its fixture answers to that test, while the
/// pictures in `docs/guides/user-guide.md` need a world with several groups,
/// a project that has logged something, a handful of accounts and an audit
/// trail. Two readers, two fixtures; `guide_fixture.dart` holds this one, so
/// what a screenshot shows is a file somebody can read and change rather
/// than whatever a stand happened to contain that afternoon.
///
/// **Semantics are switched on deliberately.** Flutter web paints into a
/// canvas, so without a semantics tree there is no DOM for a screenshot
/// script to aim at, and it would be left clicking coordinates — the failure
/// that `test_driver/live_app.dart` documents at length. With it, every
/// button and field appears as `<flt-semantics>` carrying its label, and the
/// script names what it wants.
///
/// Two query parameters choose the scene:
///
/// - `?stage=onboarding` — signed out, and the account still carries a
///   temporary password. This is the first three pictures of the guide: the
///   sign-in form, the forced change, the confirmation.
/// - `?as=user` — signed in as a plain `user` rather than an administrator,
///   which is the only way to photograph the navigation that role sees.
///
/// Without either, it is the administrator `bob`, signed in, which is who
/// the rest of the guide follows.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SemanticsBinding.instance.ensureSemantics();

  final parameters = Uri.base.queryParameters;
  final onboarding = parameters['stage'] == 'onboarding';
  final asPlainUser = parameters['as'] == 'user';

  final server = MockServer(
    username: 'bob',
    password: onboarding ? temporaryPassword : operatorPassword,
    roles: asPlainUser ? plainUserRoles : administratorRoles,
  )..mustChangePassword = onboarding;
  seedGuideWorld(server, asPlainUser: asPlainUser);

  final session = SessionController();
  final tokenStorage = InMemoryTokenStorage();
  if (!onboarding) {
    final issued = server.issueSession();
    tokenStorage.write(
      TokenPair(
        accessToken: issued.accessToken,
        refreshToken: issued.refreshToken,
      ),
    );
  }

  final scope = openAppScope(
    config: const AppConfig(baseUrl: 'https://logs.example.test'),
    logger: configureClientLogging(),
    tokenStorage: tokenStorage,
    httpAdapter: server,
    onSessionExpired: session.expire,
    onPasswordChangeRequired: session.passwordChangeRequired,
  );

  // One picture in the guide is of something *arriving* — the badge that
  // counts entries that landed while the reader was scrolled away — and a
  // screenshot script has no other way to make that happen. Everything else
  // it needs is a click.
  globalContext.setProperty(
    'guideDeliverEntries'.toJS,
    ((JSNumber howMany) {
      final open = server.streams.where((stream) => stream.isOpen);
      if (open.isEmpty) return;
      var id = 1000;
      for (var i = 0; i < howMany.toDartInt; i++) {
        open.last.send(
          mockLogEntry(
            id: ++id,
            event: 'payment_authorized',
            level: 'info',
            category: 'http',
            logger: 'checkout.api',
            receivedAt: DateTime.utc(2026, 9, 15, 9, 30 + i),
            context: {'order_id': 'ord_449${20 + i}', 'gateway': 'stripe'},
          ),
        );
      }
    }).toJS,
  );

  runApp(
    AdminApp(
      scope: scope,
      session: session,
      // English: the guide's pictures are English, and a screenshot script
      // that inherited the browser's language would produce whichever one
      // the machine happened to have.
      localeController: LocaleController(initial: const Locale('en')),
    ),
  );
}
