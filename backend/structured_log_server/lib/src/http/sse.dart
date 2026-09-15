import 'dart:convert';

/// Response headers a `text/event-stream` body needs (`log-server-live-stream`).
///
/// `no-transform` matters as much as `no-cache`: a proxy that buffers or
/// recompresses the body would hold events back until it had "enough", which
/// for a live stream means indefinitely.
const sseHeaders = <String, String>{
  'content-type': 'text/event-stream; charset=utf-8',
  'cache-control': 'no-cache, no-transform',
  'connection': 'keep-alive',
  // Nginx-specific, harmless elsewhere, and the single most common reason a
  // working SSE endpoint appears to deliver nothing once deployed.
  'x-accel-buffering': 'no',
};

/// Encodes one SSE event frame.
///
/// [data] is split on newlines into separate `data:` lines, as the format
/// requires — a single embedded newline would otherwise terminate the frame
/// early and hand the client a truncated payload.
List<int> sseEvent({int? id, String? event, required String data}) {
  final buffer = StringBuffer();
  if (id != null) buffer.write('id: $id\n');
  if (event != null) buffer.write('event: $event\n');
  for (final line in data.split('\n')) {
    buffer.write('data: $line\n');
  }
  buffer.write('\n');
  return utf8.encode(buffer.toString());
}

/// Encodes an SSE comment — the keep-alive frame. Clients ignore it; its
/// only job is to make a dead connection fail fast instead of sitting open
/// (`log-server-live-stream`).
List<int> sseComment([String text = 'heartbeat']) {
  return utf8.encode(': $text\n\n');
}

/// The terminal frame: `event: end` with a machine-readable [reason], sent
/// before the server closes a subscription it will not continue
/// (`log-server-live-stream` — a revoked token or a blocked project must not
/// leave the connection open and silent).
List<int> sseEnd(String reason) {
  return sseEvent(event: 'end', data: jsonEncode({'reason': reason}));
}
