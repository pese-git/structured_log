/// Renamed to `structured_log_remote_sync` — this package only forwards to
/// it, and receives no further releases.
///
/// Moving over is one dependency line, one import and one class name:
///
/// ```yaml
/// dependencies:
///   structured_log_remote_sync: ^0.2.0
/// ```
///
/// ```dart
/// import 'package:structured_log_remote_sync/structured_log_remote_sync.dart';
///
/// final output = RemoteSyncLogOutput(serverUrl: ..., projectSecretKey: ...);
/// ```
@Deprecated(
  'structured_log_http was renamed to structured_log_remote_sync. Import '
  'package:structured_log_remote_sync/structured_log_remote_sync.dart instead.',
)
library;

import 'package:structured_log_remote_sync/structured_log_remote_sync.dart';

export 'package:structured_log_remote_sync/structured_log_remote_sync.dart'
    show BatchResult, BatchSender;

/// The old name of [RemoteSyncLogOutput], which behaves identically.
@Deprecated(
  'Renamed to RemoteSyncLogOutput, from package:structured_log_remote_sync.',
)
typedef HttpLogOutput = RemoteSyncLogOutput;
