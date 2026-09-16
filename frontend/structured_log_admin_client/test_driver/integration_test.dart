import 'package:integration_test/integration_test_driver.dart';

/// The host half of an `integration_test` run: it starts the browser, hands it
/// the target, and collects the result. Nothing to configure — everything the
/// test needs it builds for itself.
Future<void> main() => integrationDriver();
