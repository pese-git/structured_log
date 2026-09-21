import 'dart:async';
import 'dart:collection';
import 'dart:isolate';

import 'package:cherrypick/cherrypick.dart' show Disposable;
import 'package:bcrypt/bcrypt.dart';

/// What a worker is asked to do. Sent as an index, not an enum, because only
/// plain values cross the isolate boundary cheaply.
const _opHash = 0;
const _opVerify = 1;

/// A fixed-size set of long-lived isolates that run bcrypt, so the ~130 ms each
/// computation costs is spent off the isolate serving requests.
///
/// Workers are started on demand, up to [size], and stay up: a job that
/// arrives while every worker is busy waits in a queue rather than starting
/// another isolate, which is what bounds how many cores a burst of logins can
/// take. A worker that dies mid-job fails that one job and is replaced by the
/// next that needs it.
///
/// The pool's [close] must be called on shutdown: an idle worker holds a
/// receive port open.
class HashWorkerPool implements Disposable {
  HashWorkerPool(this.size) {
    if (size < 1) throw ArgumentError.value(size, 'size', 'must be at least 1');
  }

  final int size;

  final List<_Worker> _workers = [];
  final Queue<_Job> _queue = Queue();
  bool _closed = false;

  /// Workers started so far and still alive — for tests and diagnostics.
  int get workerCount => _workers.length;

  Future<String> hash(String password) =>
      _submit(_opHash, password, null).then((r) => r as String);

  Future<bool> verify(String password, String hash) =>
      _submit(_opVerify, password, hash).then((r) => r as bool);

  Future<Object?> _submit(int op, String a, String? b) {
    if (_closed) return Future.error(StateError('HashWorkerPool is closed'));
    final job = _Job(op, a, b);
    _queue.add(job);
    _pump();
    return job.result.future;
  }

  /// Hands queued jobs to idle workers, starting workers while there is room.
  void _pump() {
    while (_queue.isNotEmpty) {
      final idle = _workers.where((w) => w.isIdle).firstOrNull;
      if (idle != null) {
        idle.run(_queue.removeFirst());
        continue;
      }
      if (_workers.length < size) {
        _startWorker();
        // The new worker is not ready yet; it pumps again when it is.
      }
      return;
    }
  }

  void _startWorker() {
    final worker = _Worker(
      onReady: _pump,
      onDied: (worker, reason, {required spawnFailed}) {
        _workers.remove(worker);
        if (_closed) return;
        if (spawnFailed) {
          // Retrying would spin: nothing can start, so nothing queued can run.
          for (final job in _queue) {
            job.result.completeError(reason);
          }
          _queue.clear();
          return;
        }
        // Jobs waiting for a slot must not be stranded by the loss of the
        // worker that was going to take them.
        _pump();
      },
    );
    _workers.add(worker);
    worker.start();
  }

  @override
  Future<void> dispose() => close();

  /// Stops every worker and fails whatever has not run.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final closing = StateError('HashWorkerPool is closed');
    for (final job in _queue) {
      job.result.completeError(closing);
    }
    _queue.clear();
    for (final worker in List.of(_workers)) {
      worker.kill(closing);
    }
    _workers.clear();
  }

  /// Kills every live worker without closing the pool, as a crash would.
  /// Only for tests.
  void debugKillWorkers() {
    for (final worker in List.of(_workers)) {
      worker.kill(StateError('worker killed'));
    }
  }
}

class _Job {
  _Job(this.op, this.a, this.b);

  final int op;
  final String a;
  final String? b;
  final Completer<Object?> result = Completer();
}

class _Worker {
  _Worker({required this.onReady, required this.onDied});

  final void Function() onReady;
  final void Function(_Worker, Object reason, {required bool spawnFailed})
  onDied;

  final ReceivePort _fromWorker = ReceivePort();
  final ReceivePort _exit = ReceivePort();
  Isolate? _isolate;
  SendPort? _toWorker;
  _Job? _current;
  bool _dead = false;

  bool get isIdle => !_dead && _toWorker != null && _current == null;

  Future<void> start() async {
    _fromWorker.listen(_onMessage);
    _exit.listen((_) => _died(StateError('hash worker exited unexpectedly')));
    try {
      _isolate = await Isolate.spawn(
        _workerMain,
        _fromWorker.sendPort,
        onExit: _exit.sendPort,
        errorsAreFatal: true,
      );
    } catch (error) {
      _died(error, spawnFailed: true);
    }
  }

  void run(_Job job) {
    _current = job;
    _toWorker!.send([job.op, job.a, job.b]);
  }

  void _onMessage(Object? message) {
    if (message is SendPort) {
      // The handshake: the worker's own port, sent once when it is up.
      _toWorker = message;
      onReady();
      return;
    }
    final job = _current;
    _current = null;
    if (job != null && message is List) {
      if (message[0] == true) {
        job.result.complete(message[1]);
      } else {
        job.result.completeError(StateError('${message[1]}'));
      }
    }
    // Free again: whatever is queued may go to this worker.
    onReady();
  }

  /// Stops the isolate; its in-flight job, if any, fails with [reason].
  void kill(Object reason) => _died(reason, killIsolate: true);

  void _died(
    Object reason, {
    bool killIsolate = false,
    bool spawnFailed = false,
  }) {
    if (_dead) return;
    _dead = true;
    if (killIsolate) _isolate?.kill(priority: Isolate.immediate);
    _fromWorker.close();
    _exit.close();
    final job = _current;
    _current = null;
    if (job != null && !job.result.isCompleted) {
      job.result.completeError(reason);
    }
    onDied(this, reason, spawnFailed: spawnFailed);
  }
}

/// The worker isolate's whole life: announce its port, then answer requests
/// until the process ends.
void _workerMain(SendPort toMain) {
  final requests = ReceivePort();
  toMain.send(requests.sendPort);
  requests.listen((Object? message) {
    final request = message as List;
    try {
      final Object result;
      switch (request[0] as int) {
        case _opHash:
          result = BCrypt.hashpw(request[1] as String, BCrypt.gensalt());
        case _opVerify:
          result = BCrypt.checkpw(request[1] as String, request[2] as String);
        default:
          throw ArgumentError('unknown operation ${request[0]}');
      }
      toMain.send([true, result]);
    } catch (error) {
      toMain.send([false, '$error']);
    }
  });
}
