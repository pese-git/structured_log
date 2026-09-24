import 'package:dio/dio.dart';
import 'package:flutter_driver/driver_extension.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:structured_log_admin_client/app/app.dart';
import 'package:structured_log_admin_client/shared/auth/session_controller.dart';
import 'package:structured_log_admin_client/shared/auth/token_pair.dart';
import 'package:structured_log_admin_client/shared/auth/token_storage.dart';
import 'package:structured_log_admin_client/shared/config/app_config.dart';
import 'package:structured_log_admin_client/shared/di/app_module.dart';
import 'package:structured_log_admin_client/shared/l10n/locale_controller.dart';
import 'package:structured_log_admin_client/shared/logging/setup.dart';

/// `main.dart`, made drivable from outside and pointed at a real server.
///
/// Unlike `app.dart` beside it, nothing is mocked: this is the shipped
/// composition talking HTTP to a running `structured_log_server`, signed
/// out, so the sign-in screen is the first thing a driver meets. It became
/// possible when the server gained `--cors-allowed-origins`; before that a
/// client on `flutter run`'s own port could not reach the API at all.
const _baseUrl = String.fromEnvironment(
  'STRUCTURED_LOG_BASE_URL',
  defaultValue: 'http://localhost:8099',
);

/// Credentials for the seeded session, supplied at build time the same way
/// the base URL is.
const _username = String.fromEnvironment(
  'DRIVE_USERNAME',
  defaultValue: 'admin',
);
const _password = String.fromEnvironment('DRIVE_PASSWORD');

/// Signs in against the real server before the first frame, when
/// `DRIVE_PASSWORD` is given.
///
/// Optional on purpose: with the sign-in form keyed, a driver can work that
/// screen itself, which is the more faithful run. Seeding a session stays
/// available for a run that wants to start behind it.
Future<TokenPair> _signIn() async {
  final dio = Dio(BaseOptions(baseUrl: _baseUrl));
  final response = await dio.post<Map<String, dynamic>>(
    '/v1/auth/token',
    data: {
      'grant_type': 'password',
      'username': _username,
      'password': _password,
    },
    options: Options(contentType: Headers.formUrlEncodedContentType),
  );
  final body = response.data!;
  return TokenPair(
    accessToken: body['access_token'] as String,
    refreshToken: body['refresh_token'] as String,
  );
}

Future<void> main() async {
  enableFlutterDriverExtension();
  WidgetsFlutterBinding.ensureInitialized();

  final log = configureClientLogging();
  final session = SessionController();
  final scope = openAppScope(
    config: const AppConfig(baseUrl: _baseUrl),
    logger: log,
    tokenStorage: _password.isEmpty
        ? null
        : InMemoryTokenStorage(await _signIn()),
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
