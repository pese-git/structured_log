import 'package:shelf/shelf.dart';

import '../config/server_config.dart';
import '../errors.dart';
import 'rate_limit/bucket_store.dart';
import 'rate_limit/client_ip.dart';
import 'rate_limit/token_bucket.dart';

const _contextKey = 'structured_log_server.rateLimitAttempt';

/// The closed list of throttled endpoints (`log-server-rate-limit`).
///
/// Closed on purpose: log ingestion, log queries and the management API are
/// deliberately absent, because what limits them is project quotas and RBAC,
/// not request frequency — an application shipping a burst of logs is doing
/// its job, and throttling it would drop data the operator asked for.
///
/// Six of these eight are not routed yet (register, the password-reset and
/// email-verification pair, and `DELETE /v1/users/me` belong to later
/// sections). They are listed anyway so the limiter is in place the moment
/// they land, rather than being a step someone has to remember.
const rateLimitedEndpoints = <({String method, String path})>[
  (method: 'POST', path: '/v1/auth/token'),
  (method: 'POST', path: '/v1/auth/register'),
  (method: 'POST', path: '/v1/auth/password-reset'),
  (method: 'POST', path: '/v1/auth/password-reset/confirm'),
  (method: 'POST', path: '/v1/auth/verify-email'),
  (method: 'POST', path: '/v1/auth/verify-email/resend'),
  (method: 'POST', path: '/v1/auth/change-password'),
  (method: 'DELETE', path: '/v1/users/me'),
];

/// What a handler uses to bring the *subject* half of the limiter to bear.
///
/// The IP half is spent by the middleware before the handler runs, because
/// a request rejected on its address shouldn't cost the server even the
/// parse of its body. The subject half can't work that way: the subject is
/// inside the body (a `username`, an `email`) or in the verified token, so
/// only the handler knows it — and whether the attempt succeeded, which is
/// what decides if a token is spent or the bucket is refilled.
///
/// The handler reports that outcome by calling [succeeded] or [failed]
/// rather than by throwing, so that "this attempt failed" stays distinct
/// from "this request failed" — a malformed body is not a failed credential
/// and must not count against the subject.
class RateLimitAttempt {
  final BucketStore? _subjects;
  final DateTime Function() _clock;
  TokenBucket? _bucket;

  RateLimitAttempt._(this._subjects, this._clock);

  /// An attempt that does nothing — the limiter is off, or this endpoint
  /// isn't throttled. Handlers call the same methods either way.
  RateLimitAttempt.inactive()
      : _subjects = null,
        _clock = DateTime.now;

  bool get isActive => _subjects != null;

  /// Registers the subject of this attempt and rejects it if that subject
  /// has no tokens left.
  ///
  /// [subject] is used exactly as submitted, with no case folding. That
  /// matches how the server looks users up — `users.username` has a
  /// case-sensitive unique index — so `Alice` and `alice` are different
  /// accounts, and folding them together here would throttle one because of
  /// attempts against the other. (Task 28.7 asks for the rule used at
  /// lookup on the grounds that case must not bypass the limiter; with a
  /// case-sensitive lookup there is nothing to bypass — a changed case is
  /// an attempt against a different account, which is the spraying case the
  /// IP bucket covers.)
  void requireSubject(String subject) {
    final subjects = _subjects;
    if (subjects == null) return;

    final bucket = subjects[subject];
    _bucket = bucket;
    final now = _clock();
    if (bucket.tokensAt(now) < 1) {
      throw ApiError.tooManyRequests(bucket.timeUntilNextToken(now));
    }
  }

  /// The credential checked out. Refills the subject's bucket: a user who
  /// can log in is not the attacker this limiter is for, and their earlier
  /// typos must not accumulate against them.
  void succeeded() => _bucket?.restore(_clock());

  /// The credential did not check out. This is the only thing that spends a
  /// subject token.
  void failed() => _bucket?.tryConsume(_clock());
}

extension RateLimitRequest on Request {
  /// The attempt [rateLimitMiddleware] installed, or an inactive one when
  /// the request never passed through it (unit tests calling a handler
  /// directly, and every endpoint that isn't throttled).
  RateLimitAttempt get rateLimitAttempt =>
      context[_contextKey] as RateLimitAttempt? ?? RateLimitAttempt.inactive();
}

/// Throttles the auth endpoints by client address and by subject
/// (`log-server-rate-limit`).
///
/// Purely in-memory and purely time-based: there is no counter in the
/// database, no lockout flag, and nothing for an administrator to clear.
/// An exhausted key recovers on its own, which is what keeps a password
/// guessing attack from being a way to lock a victim out of their own
/// account (`design.md` decision 43).
Middleware rateLimitMiddleware(
  ServerConfig config, {
  DateTime Function()? clock,
}) {
  final now = clock ?? DateTime.now;

  if (!config.rateLimitEnabled) {
    return (Handler innerHandler) => innerHandler;
  }

  final ips = BucketStore(
    capacity: config.rateLimitBucketCapacity,
    refillPerMinute: config.rateLimitRefillPerMinute,
    maxKeys: config.rateLimitMaxKeys,
    clock: now,
  );
  final subjects = BucketStore(
    capacity: config.rateLimitBucketCapacity,
    refillPerMinute: config.rateLimitRefillPerMinute,
    maxKeys: config.rateLimitMaxKeys,
    clock: now,
  );

  return (Handler innerHandler) {
    return (Request request) {
      final path = '/${request.url.path}';
      final throttled = rateLimitedEndpoints.any(
        (e) => e.method == request.method && e.path == path,
      );
      if (!throttled) return innerHandler(request);

      final ip = resolveClientIp(
        request,
        trustedProxyHops: config.trustedProxyHops,
      );
      final bucket = ips[ip];
      final at = now();
      if (!bucket.tryConsume(at)) {
        // Before the body is even read: a request rejected on its address
        // should cost the server nothing but this lookup.
        throw ApiError.tooManyRequests(bucket.timeUntilNextToken(at));
      }

      return innerHandler(
        request.change(
          context: {_contextKey: RateLimitAttempt._(subjects, now)},
        ),
      );
    };
  };
}
