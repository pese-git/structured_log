import 'refresh_cookie.dart';
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

  /// Ceilings on open live subscriptions; `0` for none. The defaults here are
  /// none, because a handler built without a `ServerConfig` — every route
  /// test — must behave as it did before there were ceilings.
  final int maxLiveSubscriptionsPerUser;
  final int maxLiveSubscriptions;

  /// Whether a token grant also sets the refresh token as an `HttpOnly`
  /// cookie, and the origins the operator has declared foreign — the pair
  /// `shouldSetRefreshCookie` needs. The default is `off` for the reason
  /// stated above: a handler built without a `ServerConfig` set no cookie
  /// before this existed and must not start now.
  final RefreshCookieMode refreshTokenCookie;
  final Set<String> corsAllowedOrigins;

  const HttpSettings({
    this.trustedProxyHops = 0,
    this.maxIngestBodyBytes = defaultMaxIngestBodyBytes,
    this.sseHeartbeatInterval = defaultSseHeartbeat,
    this.maxLiveSubscriptionsPerUser = 0,
    this.maxLiveSubscriptions = 0,
    this.refreshTokenCookie = RefreshCookieMode.off,
    this.corsAllowedOrigins = const {},
  });
}
