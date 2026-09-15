import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// One canned answer.
class FakeReply {
  final int statusCode;
  final Object? body;
  final Map<String, List<String>> headers;

  const FakeReply(this.statusCode, {this.body, this.headers = const {}});
}

/// An adapter that answers from a script instead of a socket.
///
/// Every request is recorded, which is what the interceptor tests actually
/// assert on: whether a token was attached, and how many times a request went
/// out.
class FakeAdapter implements HttpClientAdapter {
  /// Called for each request; returns the reply to give.
  final FakeReply Function(RequestOptions options) handler;

  final requests = <RequestOptions>[];

  FakeAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final reply = handler(options);
    final encoded = reply.body == null ? '' : jsonEncode(reply.body);
    return ResponseBody.fromString(
      encoded,
      reply.statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        ...reply.headers,
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
