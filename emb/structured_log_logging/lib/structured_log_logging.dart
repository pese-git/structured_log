/// Routes `package:logging` records into `structured_log`.
///
/// See [StructuredLogLoggingBridge] — attach it once, and every record a
/// library writes through `package:logging` reaches the sinks, the in-app
/// viewer and the server that `structured_log` is already configured with.
library;

export 'src/logging_bridge.dart'
    show LogLevelOf, StructuredLogLoggingBridge, defaultLogLevelOf;
