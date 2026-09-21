import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:structured_log_server/src/http/server_host.dart';
import 'package:structured_log_server/src/live/log_broadcast.dart';
import 'package:test/test.dart';

void main() {
  test('stopping ends an open subscription and stops listening', () async {
    // A subscription never ends on its own, so a process that stopped only its
    // socket could not exit: the broadcast is closed with the server.
    final broadcast = LogBroadcast();
    Stream<List<int>> body() async* {
      // A live subscription is talking: the first frame is out, and the stream
      // then stays open until the broadcast ends it.
      yield utf8.encode(': connected\n\n');
      yield* broadcast.stream.map((_) => utf8.encode('event'));
    }

    Response handler(Request request) =>
        Response.ok(body(), context: const {'shelf.io.buffer_output': false});
    final host = ServerHost(handler, broadcast, host: '127.0.0.1', port: 0);
    final server = await host.start();
    final port = server.port;

    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final request = await client.getUrl(Uri.parse('http://127.0.0.1:$port/'));
    final response = await request.close();
    final firstChunk = Completer<void>();
    final finished = Completer<void>();
    response.listen((_) {
      if (!firstChunk.isCompleted) firstChunk.complete();
    }, onDone: finished.complete);
    await firstChunk.future.timeout(const Duration(seconds: 5));

    await host.dispose().timeout(
      const Duration(seconds: 5),
      onTimeout: () => fail('stopping waited for the open subscription'),
    );

    expect(response.statusCode, 200);
    await finished.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => fail('the subscription was never ended'),
    );
    await expectLater(
      Socket.connect('127.0.0.1', port),
      throwsA(isA<SocketException>()),
      reason: 'it stopped listening',
    );
  });

  test('a host that was never started stops without complaint', () async {
    final host = ServerHost(
      (_) => Response.ok('x'),
      LogBroadcast(),
      host: '127.0.0.1',
      port: 0,
    );

    await host.dispose();
  });
}
