import 'dart:async';

import '../storage/database.dart';

/// Fans committed log entries out to every open `GET /v1/logs/stream`
/// subscription (`log-server-live-stream`).
///
/// One in-process broadcast stream, deliberately: the server already runs
/// requests in a single isolate against a single database handle
/// (`design.md` decision 4), so a subscriber is an ordinary listener in the
/// same event loop and no external pub/sub is involved. Scaling past one
/// process is an explicit non-goal, and this is one of the places that
/// would have to change first.
///
/// [publish] carries no notion of who may see an entry. Scope and filtering
/// are the subscriber's job (`LogFilter`, and the authorized project ids the
/// subscription resolved), so that a new kind of subscriber cannot acquire
/// visibility by being wired in here.
class LogBroadcast {
  final _controller = StreamController<LogEntry>.broadcast();

  /// Entries as they are committed, oldest first within a batch.
  Stream<LogEntry> get stream => _controller.stream;

  /// Whether anything is listening — publishing to nobody is the common
  /// case and is free either way, but this lets the ingest path skip the
  /// iteration entirely.
  bool get hasListeners => _controller.hasListener;

  /// Publishes [entries], which must already be committed: a subscriber
  /// that reacts by reading back from the database (catch-up) has to find
  /// them there.
  void publish(Iterable<LogEntry> entries) {
    if (_controller.isClosed) return;
    for (final entry in entries) {
      _controller.add(entry);
    }
  }

  Future<void> close() => _controller.close();
}
