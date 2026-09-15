import 'package:flutter/foundation.dart';
import 'package:structured_log/structured_log.dart';

/// The client's own diagnostics, through the workspace's own logger
/// (design.md decision 48).
///
/// Three things never enter it: passwords, tokens, and request bodies. A log
/// line carrying a token hands over a session to anyone who can read the log,
/// and the client's log is the easiest of the three to end up in a bug report
/// (`test/shared/logging/no_leak_test.dart` holds this).
///
/// This is not the log browser. Entries the user is looking at come from the
/// server over HTTP and never pass through here.
BoundLogger configureClientLogging() {
  StructlogConfiguration.configure(
    processors: [addTimestamp, addLogLevel],
    sinks: [
      LogSink(
        name: 'console',
        output: coloredConsoleOutput,
        // Debug builds say everything; a release build keeps warnings and
        // above, so a shipped client is not writing a line per request into
        // the console of whoever opens dev tools.
        minLevel: kDebugMode ? LogLevel.debug : LogLevel.warning,
      ),
    ],
  );
  return getLogger('admin_client');
}
