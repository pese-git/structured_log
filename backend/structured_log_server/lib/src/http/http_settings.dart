import 'routes/log_stream_route.dart' show defaultSseHeartbeat;
import 'routes/logs_route.dart' show defaultMaxIngestBodyBytes;

/// The knobs of the HTTP layer that routes read, in one bindable value
/// (`ServerConfig` has many more, and most are read by `bin/server.dart` alone).
///
/// Defaults are what a route used when nothing configured it, so a handler built
/// without a `ServerConfig` (route tests) behaves as it always did.
class HttpSettings {
  final int trustedProxyHops;
  final int maxIngestBodyBytes;
  final Duration sseHeartbeatInterval;

  const HttpSettings({
    this.trustedProxyHops = 0,
    this.maxIngestBodyBytes = defaultMaxIngestBodyBytes,
    this.sseHeartbeatInterval = defaultSseHeartbeat,
  });
}
