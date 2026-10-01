import 'dart:io';

import 'package:dio/dio.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_dio/structured_log_dio.dart';

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

  final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:${server.port}'))
    ..interceptors.add(StructuredLogDioInterceptor(logResponseBody: true));

  await dio.get<dynamic>('/items', queryParameters: {'access_token': 's3cr3t'});
  try {
    await dio.get<dynamic>('/missing');
  } on DioException {
    // Logged as http_error at warning; nothing else to do here.
  }

  dio.close();
  await server.close();
}
