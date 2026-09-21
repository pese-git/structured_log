/// A token bucket that refills continuously (`log-server-rate-limit`).
///
/// Refill is computed from the elapsed time on each access rather than
/// driven by a timer: a server tracking thousands of keys cannot afford a
/// timer per key, and a bucket nobody touches costs nothing to keep
/// accurate if its level is only ever derived when someone asks.
///
/// Time comes from the caller so recovery can be tested without waiting for
/// it (`tasks.md` 28.9) — and so a clock that jumps cannot hand out tokens
/// that were never earned.
class TokenBucket {
  /// Maximum tokens held, and the level a fresh bucket starts at.
  final int capacity;

  /// Tokens restored per minute, spread continuously rather than granted in
  /// one lump at the top of each minute.
  final int refillPerMinute;

  double _tokens;
  DateTime _lastRefill;
  bool _episodeRecorded = false;

  TokenBucket({
    required this.capacity,
    required this.refillPerMinute,
    required DateTime now,
  }) : _tokens = capacity.toDouble(),
       _lastRefill = now {
    if (capacity < 1) {
      throw ArgumentError.value(capacity, 'capacity', 'must be at least 1');
    }
    if (refillPerMinute < 1) {
      throw ArgumentError.value(
        refillPerMinute,
        'refillPerMinute',
        'must be at least 1, or an exhausted bucket would never recover',
      );
    }
  }

  /// Tokens available as of [now]. Exposed for tests and diagnostics; the
  /// decisions are made by [tryConsume].
  double tokensAt(DateTime now) {
    _refill(now);
    return _tokens;
  }

  /// Whether this bucket is untouched — full, and therefore carrying no
  /// information worth keeping (see `BucketStore`'s sweep).
  bool isFullAt(DateTime now) => tokensAt(now) >= capacity;

  /// Takes one token if one is available, reporting whether it succeeded.
  bool tryConsume(DateTime now) {
    _refill(now);
    if (_tokens < 1) return false;
    _tokens -= 1;
    return true;
  }

  /// Whether this refusal is the first of an episode — and marks it so the
  /// next ones are not.
  ///
  /// An episode is one continuous stretch of being empty, and it deserves one
  /// audit record, not one per refused request: an attack is a burst by
  /// definition, and a record per attempt would bury the log it is written in
  /// under the very traffic it is reporting (`specs/log-server-audit`).
  ///
  /// The flag is raised on the first **refusal**, not when the last token is
  /// spent. The request that empties the bucket is one the limiter *allowed*,
  /// and an `auth.throttled` record for a request that was served would be
  /// false. It clears in [_refill], the moment a token is available again, so
  /// a later burst is a new episode.
  bool startEpisode(DateTime now) {
    _refill(now);
    if (_episodeRecorded) return false;
    _episodeRecorded = true;
    return true;
  }

  /// Refills to capacity — what a successful authentication does to its
  /// subject's bucket, so that a legitimate user's own failures never
  /// accumulate against them across successful sessions
  /// (`log-server-rate-limit`).
  void restore(DateTime now) {
    _lastRefill = now;
    _tokens = capacity.toDouble();
    _episodeRecorded = false;
  }

  /// How long until at least one token is available, for `Retry-After`.
  /// Rounded up to whole seconds, and never negative.
  Duration timeUntilNextToken(DateTime now) {
    _refill(now);
    if (_tokens >= 1) return Duration.zero;
    final needed = 1 - _tokens;
    final seconds = needed * 60 / refillPerMinute;
    return Duration(milliseconds: (seconds * 1000).ceil());
  }

  void _refill(DateTime now) {
    final elapsed = now.difference(_lastRefill);
    // A clock that moved backwards must not drain the bucket; treat it as no
    // time having passed and resynchronize.
    if (elapsed.isNegative) {
      _lastRefill = now;
      return;
    }
    if (elapsed == Duration.zero) return;

    final earned =
        elapsed.inMicroseconds *
        refillPerMinute /
        const Duration(minutes: 1).inMicroseconds;
    _tokens = (_tokens + earned).clamp(0, capacity.toDouble());
    _lastRefill = now;
    // Out of the empty state: whatever comes next is a new episode.
    if (_tokens >= 1) _episodeRecorded = false;
  }
}
