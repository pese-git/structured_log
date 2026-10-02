import 'report_print.dart' if (dart.library.io) 'report_io.dart' as platform;

/// Reports a failure inside `structured_log` itself — a sink that threw, a
/// processor that threw, a write that failed — where a developer will see
/// it: `stderr` where `dart:io` exists, `print` where it does not (the web).
///
/// Never throws. It runs inside the code that keeps a logging call from
/// crashing its caller, so a report that cannot be delivered is dropped
/// rather than becoming the crash it was reporting on.
void reportInternalError(String message) {
  try {
    platform.platformReport(message);
  } catch (_) {
    // Nowhere left to say it.
  }
}
