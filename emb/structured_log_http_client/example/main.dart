import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_http_client/structured_log_http_client.dart';

/// Talks to a server it starts itself on the loopback interface, so the
/// example runs offline: one call that succeeds, one that answers 404.
Future<void> main() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) {
    final found = request.uri.path == '/items';
    request.response
      ..statusCode = found ? 200 : 404
      ..headers.contentType = ContentType.json
      ..write(found ? '[{"id":1}]' : '{"error":"not_found"}')
      ..close();
  });

  StructlogConfiguration.configure(
    sinks: [LogSink(name: 'console', output: coloredConsoleOutput)],
  );

  final client = StructuredLogHttpClient(http.Client(), logResponseBody: true);
  final base = Uri.parse('http://127.0.0.1:${server.port}');

  await client.get(base.resolve('/items?access_token=s3cr3t'));
  // package:http does not throw on a status: this is an http_response at
  // warning, not an exception.
  await client.get(base.resolve('/missing'));

  client.close();
  await server.close();
}
