import 'package:fluent_ui/fluent_ui.dart';

import 'app/app.dart';
import 'shared/config/app_config.dart';
import 'shared/di/app_module.dart';
import 'shared/logging/setup.dart';

/// Where the server lives, supplied at build time:
///
/// ```bash
/// flutter run --dart-define=STRUCTURED_LOG_BASE_URL=https://logs.example.com
/// ```
///
/// A compile-time define rather than a checked-in constant: the same build
/// should not carry someone else's deployment, and a client bundles no
/// configuration file to read at startup.
const _baseUrl = String.fromEnvironment(
  'STRUCTURED_LOG_BASE_URL',
  defaultValue: 'http://localhost:8080',
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Before anything that can fail, so a problem composing the app is already
  // going through the configured sink (decision 48).
  final log = configureClientLogging();
  log.info('client.starting', context: {'base_url': _baseUrl});

  final scope = openAppScope(config: const AppConfig(baseUrl: _baseUrl));

  runApp(AdminApp(scope: scope));
}
