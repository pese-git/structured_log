import 'dart:async';
import 'dart:io';

import 'package:cherrypick/cherrypick.dart' show Disposable;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../live/log_broadcast.dart';

/// The listening HTTP server, and the one place that knows how it stops.
///
/// Stopping is not only "close the socket". `HttpServer.close` returns once the
/// server has stopped listening; it does not wait for the connections it has
/// open, and a `GET /v1/logs/stream` subscription never finishes on its own — so
/// the process would sit on SIGTERM, unable to exit, until something killed it:
/// for `docker stop` ten seconds and then SIGKILL, on a SQLite database
/// mid-write. Closing the broadcast ends every subscription
/// (`log_stream_route.dart`, `onDone`), and that is done first, so no
/// subscription is still being fed while the socket goes away.
///
/// The broadcast is a dependency of the routes this server serves, and it is
/// closed *before* the server: the reverse of the order a container would
/// dispose them in, which is why it is written here rather than left to it.
class ServerHost implements Disposable {
  final Handler _handler;
  final LogBroadcast _broadcast;
  final String host;
  final int port;

  HttpServer? _server;

  ServerHost(
    this._handler,
    this._broadcast, {
    required this.host,
    required this.port,
  });

  /// Starts listening. The address is what the OS bound, so a configured port of
  /// `0` reports the one it got.
  Future<HttpServer> start() async {
    return _server = await shelf_io.serve(_handler, host, port);
  }

  @override
  Future<void> dispose() async {
    await _broadcast.close();
    await _server?.close(force: false);
    _server = null;
  }
}
