import 'package:drift/native.dart';
import 'package:shelf/shelf.dart';
import 'package:structured_log_server/src/http/server.dart';
import 'package:structured_log_server/src/storage/database.dart';
import 'package:test/test.dart';

/// The server answers no browser from another origin, and that is the whole
/// deployment model rather than an oversight.
///
/// There is no CORS here and never was: the bundled deployment serves the
/// admin client beside the API behind one nginx, and the client's bundle is
/// built with an empty base URL for exactly that reason. Opening the API to a
/// third-party origin is a change to the server — a decision someone makes —
/// not a proxy setting.
///
/// Which is why this test exists. Absence needs no implementation, but it does
/// need to stay absent: a CORS middleware added in passing, to unblock someone
/// running the client on its own port, would quietly turn a closed API into an
/// open one and nothing else in the suite would notice
/// (`specs/log-server-api`).
void main() {
  late StructuredLogDatabase db;
  late Handler handler;

  setUp(() {
    db = StructuredLogDatabase(NativeDatabase.memory());
    handler = buildHandler(db, signingSecret: 'test-secret', issuer: 'test');
  });

  tearDown(() => db.close());

  /// Every header a browser reads before it will hand a cross-origin response
  /// to the page that asked for it.
  const crossOriginHeaders = [
    'access-control-allow-origin',
    'access-control-allow-credentials',
    'access-control-allow-headers',
    'access-control-allow-methods',
    'access-control-expose-headers',
  ];

  // `Future.value`, because a `Handler` returns `FutureOr<Response>`: parts
  // of this pipeline answer synchronously, and awaiting the union directly
  // is not the same type.
  Future<Response> from(String origin, {required String path}) =>
      Future<Response>.value(
        handler(
          Request(
            'GET',
            Uri.parse('http://logs.example.test$path'),
            headers: {'origin': origin},
          ),
        ),
      );

  test('a public endpoint allows no origin', () async {
    final response = await from('http://elsewhere.test', path: '/healthz');

    expect(response.statusCode, 200, reason: 'the request itself is served');
    for (final header in crossOriginHeaders) {
      expect(
        response.headers,
        isNot(contains(header)),
        reason:
            'a browser that receives this without $header cannot hand it to '
            'the page — which is the intended answer, not a bug',
      );
    }
  });

  test('an authenticated endpoint allows no origin either', () async {
    // Refused for want of a token, which is beside the point: what matters is
    // that even the refusal carries no permission to read it cross-origin.
    final response = await from('http://elsewhere.test', path: '/v1/groups');

    expect(response.statusCode, 401);
    for (final header in crossOriginHeaders) {
      expect(response.headers, isNot(contains(header)));
    }
  });

  test('a preflight is not a case the server knows', () async {
    final response = await Future<Response>.value(
      handler(
        Request(
          'OPTIONS',
          Uri.parse('http://logs.example.test/v1/logs'),
          headers: {
            'origin': 'http://elsewhere.test',
            'access-control-request-method': 'POST',
          },
        ),
      ),
    );

    expect(
      response.statusCode,
      isNot(200),
      reason: 'no route answers OPTIONS, and none should: a preflight that '
          'succeeded would be the first half of a CORS policy',
    );
    expect(response.headers, isNot(contains('access-control-allow-origin')));
  });
}
