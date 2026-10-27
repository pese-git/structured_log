import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_shelf/structured_log_shelf.dart';

/// Serves on the loopback interface and calls itself, so the example runs
/// offline: one request that succeeds, one the handler refuses, and one
/// whose handler throws.
Future<void> main() async {
  StructlogConfiguration.configure(
    sinks: [LogSink(name: 'console', output: jsonLineOutput)],
  );

  final handler = const Pipeline()
      .addMiddleware(structuredLogRequests())
      .addHandler(_route);
  final server = await shelf_io.serve(handler, InternetAddress.loopbackIPv4, 0);

  final client = HttpClient();
  for (final path in ['/items?access_token=s3cr3t', '/quota', '/broken']) {
    final response =
        await (await client.get('127.0.0.1', server.port, path)).close();
    await response.drain<void>();
    stdout.writeln('$path -> ${response.statusCode}, '
        'X-Request-Id: ${response.headers.value('x-request-id')}');
  }

  client.close();
  await server.close();
}

Response _route(Request request) {
  switch (request.url.path) {
    case 'items':
      // Carries the same request_id as the middleware's entry.
      request.logger.info('items_listed', context: {'count': 1});
      return Response.ok('[{"id":1}]');
    case 'quota':
      request.logger.warning('quota_exceeded');
      return Response(429);
    default:
      // shelf_io turns it into a 500; the middleware writes
      // http_request_failed with the stack first.
      throw StateError('no handler for ${request.url.path}');
  }
}
