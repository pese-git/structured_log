import 'package:flutter_driver/driver_extension.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:structured_log_admin_client/app/app.dart';
import 'package:structured_log_admin_client/shared/auth/session_controller.dart';
import 'package:structured_log_admin_client/shared/auth/token_pair.dart';
import 'package:structured_log_admin_client/shared/auth/token_storage.dart';
import 'package:structured_log_admin_client/shared/config/app_config.dart';
import 'package:structured_log_admin_client/shared/di/app_module.dart';
import 'package:structured_log_admin_client/shared/logging/setup.dart';
import 'package:structured_log_admin_client/testing/mock_server.dart';

/// The application, made drivable from outside, on a mocked network.
///
/// The mock is not a convenience here — it is the only way this runs in a
/// browser at all. The server has no CORS and never had any: the bundled
/// deployment serves the client beside the API behind one nginx, so a client
/// on `flutter run`'s own port cannot reach an API on another, and an app
/// launched this way shows "Сервер недоступен" and nothing else. Which is
/// also the first thing this harness established.
///
/// Everything above the adapter is the shipped composition: the same scope,
/// the same session controller, the same screens.
void main() {
  enableFlutterDriverExtension();
  WidgetsFlutterBinding.ensureInitialized();

  final server = MockServer(username: 'admin', password: 'operator-password');
  server.groups.add({
    'id': 1,
    'name': 'payments',
    'created_at': '2026-02-14T00:00:00.000Z',
  });
  server.projects.add({
    'id': 1,
    'group_id': 1,
    'name': 'checkout',
    'retention_days': 30,
    'max_entries': null,
    'max_bytes': null,
    'is_blocked': false,
    'created_at': '2026-02-14T00:00:00.000Z',
    'entry_count': 0,
    'total_bytes': 0,
  });
  final issued = server.issueSession();

  final session = SessionController();
  final scope = openAppScope(
    config: const AppConfig(baseUrl: 'https://logs.example.test'),
    logger: configureClientLogging(),
    tokenStorage: InMemoryTokenStorage(
      TokenPair(
        accessToken: issued.accessToken,
        refreshToken: issued.refreshToken,
      ),
    ),
    httpAdapter: server,
    onSessionExpired: session.expire,
    onPasswordChangeRequired: session.passwordChangeRequired,
  );

  runApp(AdminApp(scope: scope, session: session));
}
