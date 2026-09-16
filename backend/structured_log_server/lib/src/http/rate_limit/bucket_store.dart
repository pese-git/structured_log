import 'dart:collection';

import 'token_bucket.dart';

/// Holds the rate limiter's buckets, in memory only.
///
/// Nothing here reaches the database, by design: the limiter is throttling,
/// not lockout (`log-server-rate-limit`, `design.md` decision 43). State
/// that survived a restart would turn a burst into something an
/// administrator has to clear, which is precisely what the requirement
/// rules out.
///
/// Two things keep memory bounded. A full bucket carries no information —
/// it is indistinguishable from one that has never been seen — so a
/// periodic sweep drops them. What the sweep doesn't reclaim, [maxKeys]
/// does: past that many keys the least recently used is evicted, which at
/// worst forgives a key that was being throttled.
class BucketStore {
  final int capacity;
  final int refillPerMinute;

  /// Upper bound on buckets kept. Reaching it means an attacker is cycling
  /// keys faster than the sweep reclaims them.
  final int maxKeys;

  /// How often the full-bucket sweep runs. It is performed lazily on access
  /// rather than from a `Timer`: a timer owned by a store has to be
  /// cancelled by whoever owns the store, and a rate limiter that leaks a
  /// timer keeps a test — or a shutting-down server — alive.
  final Duration sweepInterval;

  final DateTime Function() _clock;

  /// Insertion-ordered, and re-inserted on access, so the first key is
  /// always the least recently used.
  final LinkedHashMap<String, TokenBucket> _buckets = LinkedHashMap();

  DateTime _lastSweep;

  BucketStore({
    required this.capacity,
    required this.refillPerMinute,
    required this.maxKeys,
    required DateTime Function() clock,
    this.sweepInterval = const Duration(minutes: 1),
  })  : _clock = clock,
        _lastSweep = clock() {
    if (maxKeys < 1) {
      throw ArgumentError.value(maxKeys, 'maxKeys', 'must be at least 1');
    }
  }

  /// Buckets currently held — for tests and diagnostics.
  int get length => _buckets.length;

  /// The bucket for [key], creating a full one if this key is new.
  TokenBucket operator [](String key) {
    _sweepIfDue();

    final existing = _buckets.remove(key);
    if (existing != null) {
      // Re-inserted at the end: LinkedHashMap keeps insertion order, so
      // this is what makes the first entry the least recently used.
      _buckets[key] = existing;
      return existing;
    }

    final fresh = TokenBucket(
      capacity: capacity,
      refillPerMinute: refillPerMinute,
      now: _clock(),
    );
    _buckets[key] = fresh;
    _evictWhileOverCapacity();
    return fresh;
  }

  void _evictWhileOverCapacity() {
    while (_buckets.length > maxKeys) {
      _buckets.remove(_buckets.keys.first);
    }
  }

  void _sweepIfDue() {
    final now = _clock();
    if (now.difference(_lastSweep) < sweepInterval) return;
    _lastSweep = now;
    _buckets.removeWhere((_, bucket) => bucket.isFullAt(now));
  }
}
