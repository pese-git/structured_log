import 'dart:convert';
import 'dart:io';

import 'package:cherrypick/cherrypick.dart' show Disposable;
import 'package:structured_log/structured_log.dart';

import '../config/config_resolver.dart';
import '../config/param_spec.dart';
import '../config/server_config.dart';

/// The server's own diagnostic log — its third journal, and the one that
/// must never be confused with the other two (`design.md` decision 48).
///
/// `log_entries` holds tenants' business data, arriving over `POST /v1/logs`;
/// `audit_log_entries` holds administrative and authentication facts, which
/// are the record an incident is reconstructed from. This is neither: it is
/// what the process itself did. Diagnostics must not reach `log_entries` —
/// they belong to no project and would distort someone's quota — and must
/// not stand in for the audit log, which cannot be turned down by a level.
class ServerLogging implements Disposable {
  /// The root logger. Handlers derive from it with `bind`/`withCorrelation`
  /// rather than reaching for a global.
  final BoundLogger logger;

  final AsyncRotatingFileOutput? _file;

  ServerLogging._(this.logger, this._file);

  /// Waits for queued file writes to land. Called before the process exits;
  /// without it the last lines of a clean shutdown can be lost.
  Future<void> flush() async => _file?.flushed;

  /// A scope that owns the logging flushes it last, after everything that
  /// could still write a line has gone down.
  @override
  Future<void> dispose() => flush();
}

/// Configures `structured_log` for this process and returns the root logger.
///
/// Call before the HTTP server starts, so that anything the startup path
/// reports is already going through the configured sinks.
///
/// With no `logFile`, output goes to the console in the configured format.
/// With one, it goes to a rotating file instead — asynchronously, because
/// the server runs every request in one isolate (`design.md` decision 4) and
/// a synchronous write per request would block all of them. A file is always
/// JSON lines; `logFormat` governs the console, where a human may be
/// reading.
ServerLogging configureServerLogging(ServerConfig config) {
  final level = parseLogLevel(config.logLevel);
  final logFile = config.logFile;

  AsyncRotatingFileOutput? file;
  final OutputFunction output;
  if (logFile != null && logFile.isNotEmpty) {
    file = AsyncRotatingFileOutput(
      logFile,
      maxSizeBytes: config.logMaxFileBytes,
      maxBackups: config.logMaxFiles,
    );
    output = file.call;
  } else {
    output = config.logFormat == 'json' ? jsonLineOutput : coloredConsoleOutput;
  }

  StructlogConfiguration.configure(
    sinks: [LogSink(name: 'server', output: output, minLevel: level)],
  );

  return ServerLogging._(getLogger(), file);
}

/// One entry per line, as compact JSON — what a log shipper expects, and
/// what `defaultOutput`'s indented form is not.
void jsonLineOutput(Map<String, dynamic> entry, LogLevel level) {
  stdout.writeln(jsonEncode(entry));
}

/// Parses a configured level name. Unknown values fall back to `info`
/// rather than throwing: refusing to start over a log level would be a
/// worse failure than logging slightly more than asked.
LogLevel parseLogLevel(String name) {
  for (final level in LogLevel.values) {
    if (level.name == name) return level;
  }
  return LogLevel.info;
}

/// The effective configuration as log context, with every secret masked the
/// same way `--print-config` masks it.
///
/// Logged once at startup: when something misbehaves in a deployment, the
/// first question is always which settings were actually in force, and
/// answering it from the log beats asking an operator to re-run the process
/// with a different flag.
Map<String, Object?> maskedConfigContext(
  List<ParamSpec> specs,
  Map<String, ResolvedValue> values,
) {
  final context = <String, Object?>{};
  for (final spec in specs) {
    final resolved = values[spec.name];
    if (resolved == null) continue;
    context[spec.name.replaceAll('-', '_')] = spec.isSecret
        ? (resolved.value == null ? null : '***')
        : resolved.value;
  }
  return context;
}
