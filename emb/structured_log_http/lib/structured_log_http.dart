/// Ships `structured_log` entries to a `structured_log_server` over HTTP.
///
/// See [HttpLogOutput] — a batching, retrying `OutputFunction` that plugs
/// into a `LogSink` without any change to the core package.
library;

export 'src/http_output.dart' show BatchResult, BatchSender, HttpLogOutput;
