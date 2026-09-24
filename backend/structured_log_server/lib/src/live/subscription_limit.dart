import 'package:meta/meta.dart';

/// A place in the live-stream ceiling, held for as long as one subscription
/// is open.
///
/// [release] is idempotent on purpose, and that is the point of the class
/// rather than a nicety. The route reaches its teardown twice — once when it
/// ends the stream itself, and again when closing the body cancels the
/// controller — so a plain `count--` at that spot would count one
/// subscription out twice. The counter would then sit below the truth and
/// drift further with every stream, until a ceiling that is still configured
/// stops being enforced. Nothing about that failure is visible: no error, no
/// log line, just a limit that quietly is not one.
class SubscriptionSlot {
  final void Function() _onRelease;
  var _released = false;

  SubscriptionSlot._(this._onRelease);

  /// Gives the place back. Safe to call any number of times; only the first
  /// does anything.
  void release() {
    if (_released) return;
    _released = true;
    _onRelease();
  }

  /// Whether this slot has already been given back — for tests, which have
  /// no other way to tell one release from three.
  @visibleForTesting
  bool get isReleased => _released;
}

/// How many live subscriptions may be open at once, per account and across
/// the process (`log-server-live-stream`).
///
/// Two ceilings rather than one, because each alone leaves the other case
/// open. An account ceiling on its own does nothing about many accounts, and
/// a deployment where accounts are cheap — or one where several have been
/// taken — is exactly the case worth surviving. A process ceiling on its own
/// lets one greedy client fill the server and shut everyone else out.
///
/// Either ceiling set to zero means no ceiling, the same reading
/// `db-read-pool-size` gives zero.
///
/// What this cannot do is notice a client that vanished. TCP does not tell
/// the server; the server finds out when it next writes to the socket, which
/// for an idle subscription is the next heartbeat. So an abandoned connection
/// keeps its place for up to `--sse-heartbeat-interval-seconds`, and the
/// ceiling is that much softer than the number suggests — measured on a
/// running server: with a one-second heartbeat the place came back in one
/// second, with the default twenty-five it takes that long. Shortening the
/// heartbeat tightens the ceiling and costs a write per subscription per
/// tick.
class SubscriptionLimiter {
  /// Most subscriptions one account may hold at once; `0` for no limit.
  final int perUser;

  /// Most subscriptions this process may hold at once; `0` for no limit.
  final int total;

  final _byUser = <int, int>{};
  var _total = 0;

  SubscriptionLimiter({required this.perUser, required this.total});

  /// Takes a place for [userId], or answers `null` when either ceiling is
  /// already full.
  ///
  /// A refusal spends nothing: the account's count is untouched, so being
  /// turned away by the process ceiling does not also cost the caller room
  /// of their own.
  SubscriptionSlot? tryAcquire(int userId) {
    if (total > 0 && _total >= total) return null;
    final held = _byUser[userId] ?? 0;
    if (perUser > 0 && held >= perUser) return null;

    _byUser[userId] = held + 1;
    _total++;
    return SubscriptionSlot._(() => _release(userId));
  }

  void _release(int userId) {
    final held = _byUser[userId];
    // Unreachable through `SubscriptionSlot`, which releases once and only
    // for an account it counted. Written defensively anyway, because the
    // failure it would cause — a count below the truth — is silent.
    if (held == null || held <= 0) return;
    if (held == 1) {
      // Dropped rather than left at zero: the map is keyed by account id, and
      // an entry that never goes away is a leak an account-creating flood can
      // grow.
      _byUser.remove(userId);
    } else {
      _byUser[userId] = held - 1;
    }
    _total--;
  }

  /// How many subscriptions [userId] holds right now.
  int held(int userId) => _byUser[userId] ?? 0;

  /// How many subscriptions this process holds right now.
  int get openTotal => _total;

  /// How many accounts have a count kept for them — the size of what this
  /// object remembers, which tests assert does not grow.
  @visibleForTesting
  int get trackedAccounts => _byUser.length;
}
