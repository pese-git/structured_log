import 'dart:convert';

import 'package:structured_log_server/src/http/sse.dart';
import 'package:test/test.dart';

String decode(List<int> frame) => utf8.decode(frame);

void main() {
  // The wire format has no library behind it — these few functions *are*
  // the protocol, and a malformed frame is not a failed request but a
  // client that silently sees the wrong thing (a truncated payload, or an
  // event it never receives).
  group('sseEvent', () {
    test(
      'writes id, event and data in that order, ending with a blank line',
      () {
        expect(
          decode(sseEvent(id: 7, event: 'log', data: '{"a":1}')),
          'id: 7\nevent: log\ndata: {"a":1}\n\n',
        );
      },
    );

    test('omits id and event when absent', () {
      expect(decode(sseEvent(data: 'x')), 'data: x\n\n');
    });

    test('splits multi-line data across data: lines', () {
      // A single embedded newline would otherwise end the frame early and
      // hand the client half a payload.
      expect(
        decode(sseEvent(data: 'first\nsecond')),
        'data: first\ndata: second\n\n',
      );
    });

    test('keeps an empty data line rather than emitting no data at all', () {
      expect(decode(sseEvent(data: '')), 'data: \n\n');
    });

    test('encodes non-ASCII as UTF-8', () {
      final frame = sseEvent(data: 'привет');
      expect(decode(frame), 'data: привет\n\n');
      expect(
        frame.length,
        greaterThan('data: привет\n\n'.length),
        reason: 'multi-byte characters',
      );
    });
  });

  group('sseComment', () {
    test('is a comment frame, which carries no event', () {
      expect(decode(sseComment()), ': heartbeat\n\n');
      expect(decode(sseComment('ping')), ': ping\n\n');
    });
  });

  group('sseEnd', () {
    test('is an event named end carrying a machine-readable reason', () {
      final text = decode(sseEnd('token_revoked'));
      expect(text, startsWith('event: end\n'));
      final data = text
          .split('\n')
          .firstWhere((l) => l.startsWith('data: '))
          .substring(6);
      expect(jsonDecode(data), {'reason': 'token_revoked'});
    });
  });

  group('sseHeaders', () {
    test('declares an event stream', () {
      expect(sseHeaders['content-type'], contains('text/event-stream'));
    });

    test('opts out of every layer that would buffer or transform the body', () {
      // Each of these is a real way for a working endpoint to appear dead:
      // a cache holding the response, a proxy recompressing it, or nginx
      // collecting it before forwarding.
      expect(sseHeaders['cache-control'], contains('no-cache'));
      expect(sseHeaders['cache-control'], contains('no-transform'));
      expect(sseHeaders['x-accel-buffering'], 'no');
    });
  });
}
