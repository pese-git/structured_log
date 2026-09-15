import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:web/web.dart' as web;

/// On the web, dio cannot stream a response — so the live log subscription
/// gets an adapter that can.
///
/// dio's browser adapter drives `XMLHttpRequest` with
/// `responseType = 'arraybuffer'` and completes the body inside `onLoad`:
/// the bytes are handed over once, when the response has finished. For an
/// ordinary request that is invisible. For `GET /v1/logs/stream`, which is
/// designed never to finish, it means the connection opens, answers 200, and
/// then delivers nothing for as long as it stays healthy — which is exactly
/// what it did until this existed.
///
/// `fetch` reads the body as a `ReadableStream` and takes arbitrary request
/// headers, so the contract does not have to move: the subscription keeps its
/// `Authorization: Bearer` (`log-server-live-stream`, design.md decision 29)
/// instead of falling back to `EventSource`, which cannot send one and would
/// have forced the token into the URL.
///
/// **Only the live stream runs through this.** It is installed on its own
/// `Dio` instance (`ApiClient.streamDio`) rather than replacing the browser
/// adapter everywhere: every other request is a small JSON document that the
/// stock adapter already handles, and a hand-written adapter serving all of
/// them would have to be a complete one.
HttpClientAdapter? createStreamingAdapter() => FetchStreamingAdapter();

class FetchStreamingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final headers = web.Headers();
    options.headers.forEach((name, value) {
      if (value != null) headers.append(name, '$value');
    });

    final abort = web.AbortController();
    // Closing the subscription has to close the socket. Without this a
    // reader that nobody is listening to keeps the connection open, and the
    // server keeps a subscriber it will never deliver to.
    unawaited(cancelFuture?.whenComplete(() => abort.abort()));

    final web.Response response;
    try {
      response = await web.window
          .fetch(
            options.uri.toString().toJS,
            web.RequestInit(
              method: options.method,
              headers: headers,
              signal: abort.signal,
            ),
          )
          .toDart;
    } catch (error) {
      // `fetch` rejects for a refused connection, a DNS failure, or an abort,
      // and says nothing about which — the browser withholds the detail on
      // purpose. dio's own adapters report the same shape.
      throw DioException.connectionError(
        requestOptions: options,
        reason: '$error',
      );
    }

    final status = response.status;
    final responseHeaders = _headersOf(response);

    // A refusal is a complete, short document, and the caller wants its body
    // rather than a stream of it.
    final body = response.body;
    if (status >= 400 || body == null) {
      final buffer = await response.arrayBuffer().toDart;
      return ResponseBody.fromBytes(
        buffer.toDart.asUint8List(),
        status,
        headers: responseHeaders,
        statusMessage: response.statusText,
      );
    }

    return ResponseBody(
      _chunks(body, abort),
      status,
      headers: responseHeaders,
      statusMessage: response.statusText,
    );
  }

  /// The response headers this client actually reads.
  ///
  /// `Headers` has no enumeration in `package:web`, and copying the lot would
  /// mean reaching into JS iteration for values nothing consults. `content-type`
  /// is what dio inspects; `retry-after` is what a 429 is read through
  /// (`failure_mapper.dart`).
  static Map<String, List<String>> _headersOf(web.Response response) {
    final headers = <String, List<String>>{};
    for (final name in const ['content-type', 'retry-after']) {
      final value = response.headers.get(name);
      if (value != null) headers[name] = [value];
    }
    return headers;
  }

  /// The body, chunk by chunk, as the network delivers it.
  static Stream<Uint8List> _chunks(
    web.ReadableStream body,
    web.AbortController abort,
  ) {
    final reader = web.ReadableStreamDefaultReader(body);
    late StreamController<Uint8List> controller;
    var stopped = false;

    Future<void> pump() async {
      try {
        while (!stopped) {
          final chunk = await reader.read().toDart;
          if (chunk.done || stopped) break;
          final value = chunk.value;
          if (value == null) continue;
          controller.add((value as JSUint8Array).toDart);
        }
      } catch (error) {
        // An aborted read throws; that is this client hanging up, not a
        // failure worth reporting to it.
        if (!stopped && !controller.isClosed) controller.addError(error);
      } finally {
        if (!controller.isClosed) await controller.close();
      }
    }

    controller = StreamController<Uint8List>(
      onListen: () => unawaited(pump()),
      onCancel: () {
        stopped = true;
        abort.abort();
      },
    );
    return controller.stream;
  }

  @override
  void close({bool force = false}) {}
}
