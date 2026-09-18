import 'package:flutter_driver/driver_extension.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:structured_log_admin_client/shared/l10n/locale_controller.dart';
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
  // The audit log, seeded to match what a real server writes — the shapes
  // copied from a stand: a quota change carrying both halves, a key created
  // and revoked without its value, a failed login under an account that
  // exists and one under an account that does not, and a throttling episode.
  server
    ..auditRetentionDays = 365
    ..authEventRetentionDays = 90;
  server.auditEntries.addAll([
    mockAuditEntry(
      id: 1,
      action: 'auth.login_succeeded',
      actorUserId: 1,
      targetId: 1,
      metadata: const {
        'client_ip': '203.0.113.7',
        'user_agent': 'structured_log_admin_client/0.1.0',
      },
      createdAt: DateTime.utc(2026, 9, 13, 6, 30),
    ),
    mockAuditEntry(
      id: 2,
      action: 'group.created',
      targetType: 'group',
      actorUserId: 1,
      targetId: 1,
      metadata: const {'name': 'payments'},
      createdAt: DateTime.utc(2026, 9, 13, 6, 32),
    ),
    mockAuditEntry(
      id: 3,
      action: 'project.quota_updated',
      targetType: 'project',
      actorUserId: 1,
      targetId: 1,
      metadata: const {
        'before': {
          'retention_days': 30,
          'max_entries': 2000,
          'max_bytes': null,
        },
        'after': {'retention_days': 30, 'max_entries': null, 'max_bytes': null},
      },
      createdAt: DateTime.utc(2026, 9, 13, 6, 40),
    ),
    mockAuditEntry(
      id: 4,
      action: 'secret_key.created',
      targetType: 'secret_key',
      actorUserId: 1,
      targetId: 1,
      metadata: const {'project_id': 1, 'label': 'CI pipeline'},
      createdAt: DateTime.utc(2026, 9, 13, 6, 45),
    ),
    mockAuditEntry(
      id: 5,
      action: 'secret_key.revoked',
      targetType: 'secret_key',
      actorUserId: 1,
      targetId: 1,
      metadata: const {'project_id': 1, 'label': 'CI pipeline'},
      createdAt: DateTime.utc(2026, 9, 13, 6, 50),
    ),
    mockAuditEntry(
      id: 6,
      action: 'auth.login_failed',
      actorUserId: 1,
      targetId: 1,
      metadata: const {
        'reason': 'invalid_password',
        'client_ip': '203.0.113.7',
        'user_agent': 'curl/8.7.1',
      },
      createdAt: DateTime.utc(2026, 9, 13, 7),
    ),
    mockAuditEntry(
      id: 7,
      action: 'auth.login_failed',
      metadata: const {
        'reason': 'unknown_user',
        'unknown_user': true,
        'client_ip': '198.51.100.44',
        'user_agent': 'curl/8.7.1',
      },
      createdAt: DateTime.utc(2026, 9, 13, 7, 2),
    ),
    mockAuditEntry(
      id: 8,
      action: 'auth.throttled',
      targetType: 'auth',
      metadata: const {
        'key_kind': 'ip',
        'path': '/v1/auth/token',
        'client_ip': '198.51.100.44',
      },
      createdAt: DateTime.utc(2026, 9, 13, 7, 3),
    ),
    mockAuditEntry(
      id: 9,
      action: 'audit.purged',
      targetType: 'audit',
      metadata: const {
        'scope': 'auth',
        'deleted_count': 18432,
        'older_than': '2026-06-14T03:00:00.000Z',
      },
      createdAt: DateTime.utc(2026, 9, 13, 7, 10),
    ),
  ]);

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

  runApp(
    AdminApp(
      scope: scope,
      session: session,
      localeController: LocaleController(initial: const Locale('ru')),
    ),
  );
}
