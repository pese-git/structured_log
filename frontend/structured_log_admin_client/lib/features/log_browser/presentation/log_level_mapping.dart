import 'package:structured_log_admin_ui/structured_log_admin_ui.dart';

/// The server's level string into the component library's enum.
///
/// The boundary where the API's vocabulary becomes the UI's: the library
/// deliberately has no dependency on this client or on `structured_log`, so
/// somebody has to do this, and doing it once here keeps every screen from
/// inventing its own mapping.
AdminLogLevel logLevelOf(String level) {
  switch (level.toLowerCase()) {
    case 'trace':
      return AdminLogLevel.trace;
    case 'debug':
      return AdminLogLevel.debug;
    case 'warning':
      return AdminLogLevel.warning;
    case 'error':
      return AdminLogLevel.error;
    case 'critical':
      return AdminLogLevel.critical;
    case 'info':
    default:
      // An unknown level is shown rather than hidden: the entry exists, and
      // treating it as info is less wrong than dropping the row.
      return AdminLogLevel.info;
  }
}
