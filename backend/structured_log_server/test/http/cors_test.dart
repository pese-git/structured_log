import 'package:drift/native.dart';
import 'package:shelf/shelf.dart';
import 'package:structured_log_server/src/config/server_config.dart';
import 'package:structured_log_server/src/http/server.dart';
import 'package:structured_log_server/src/storage/database.dart';
import 'package:test/test.dart';

/// By default the server answers no browser from another origin, and that is
/// the whole deployment model rather than an oversight.
///
/// There is no CORS unless an operator explicitly turns it on: the bundled
/// deployment serves the admin client beside the API behind one nginx, and
/// the client's bundle is built with an empty base URL for exactly that
/// reason. Opening the API to a third-party origin is a change to the
/// server's configuration — a decision someone makes, naming the origin — not
/// something a proxy setting or an unconditional middleware should do on its
/// own.
///
/// The first group below pins that default: with no `config` (and so no
/// `corsAllowedOrigins`), absence needs no implementation, but it does need
/// to stay absent. The second group covers what changes for an origin an
/// operator has explicitly named (`specs/log-server-api`).
/// A [ServerConfig] with only the fields this suite cares about set to
/// anything meaningful — same pattern as `rate_limit_middleware_test.dart`'s
/// `configWith`.
ServerConfig configWith({
  Set<String> corsAllowedOrigins = const {},
  bool rateLimitEnabled = false,
  int rateLimitBucketCapacity = 10,
}) {
  return ServerConfig(
    dbPath: ':memory:',
    httpHost: 'localhost',
    httpPort: 0,
    jwtSecret: 'test-secret',
    jwtIssuer: 'test',
    maxIngestBodyBytes: 1024 * 1024,
    retentionPurgeIntervalSeconds: 3600,
    bootstrapAdminEnabled: false,
    bootstrapAdminUsername: 'root',
    bootstrapAdminPassword: null,
    logLevel: 'info',
    logFile: null,
    logFormat: 'json',
    logMaxFileBytes: 1024,
    logMaxFiles: 1,
    rateLimitEnabled: rateLimitEnabled,
    rateLimitBucketCapacity: rateLimitBucketCapacity,
    rateLimitRefillPerMinute: 60,
    rateLimitMaxKeys: 1000,
    trustedProxyHops: 0,
    sseHeartbeatIntervalSeconds: 30,
    corsAllowedOrigins: corsAllowedOrigins,
  );
}

void main() {
  late StructuredLogDatabase db;

  setUp(() {
    db = StructuredLogDatabase(NativeDatabase.memory());
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

  group('CORS disabled by default', () {
    late Handler handler;

    setUp(() {
      handler = buildHandler(db, signingSecret: 'test-secret', issuer: 'test');
    });

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

      expect(
        response.statusCode,
        200,
        reason: 'the request itself is served',
      );
      for (final header in crossOriginHeaders) {
        expect(
          response.headers,
          isNot(contains(header)),
          reason: 'a browser that receives this without $header cannot hand it '
              'to the page — which is the intended answer, not a bug',
        );
      }
    });

    test('an authenticated endpoint allows no origin either', () async {
      // Refused for want of a token, which is beside the point: what matters
      // is that even the refusal carries no permission to read it
      // cross-origin.
      final response = await from(
        'http://elsewhere.test',
        path: '/v1/groups',
      );

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
        reason: 'no route answers OPTIONS, and none should: a preflight '
            'that succeeded would be the first half of a CORS policy',
      );
      expect(
        response.headers,
        isNot(contains('access-control-allow-origin')),
      );
    });
  });

  group('an explicitly allowed origin', () {
    const allowed = 'http://dev.example.test';
    late Handler handler;

    setUp(() {
      handler = buildHandler(
        db,
        signingSecret: 'test-secret',
        issuer: 'test',
        config: configWith(corsAllowedOrigins: {allowed}),
      );
    });

    Future<Response> get(String origin, {required String path}) =>
        Future<Response>.value(
          handler(
            Request(
              'GET',
              Uri.parse('http://logs.example.test$path'),
              headers: {'origin': origin},
            ),
          ),
        );

    Future<Response> preflight(String origin, {required String path}) =>
        Future<Response>.value(
          handler(
            Request(
              'OPTIONS',
              Uri.parse('http://logs.example.test$path'),
              headers: {
                'origin': origin,
                'access-control-request-method': 'POST',
              },
            ),
          ),
        );

    test('a public endpoint response carries the header', () async {
      final response = await get(allowed, path: '/healthz');

      expect(response.statusCode, 200);
      expect(response.headers['access-control-allow-origin'], allowed);
      expect(response.headers['vary'], 'Origin');
    });

    test('an error response carries the header too', () async {
      // 401 for want of a token — the point is that the browser needs the
      // header on *this* response to be allowed to read the refusal at all.
      final response = await get(allowed, path: '/v1/groups');

      expect(response.statusCode, 401);
      expect(response.headers['access-control-allow-origin'], allowed);
    });

    test(
      'a preflight for the allowed origin gets 204 and the CORS headers',
      () async {
        final response = await preflight(allowed, path: '/v1/logs');

        expect(response.statusCode, 204);
        expect(response.headers['access-control-allow-origin'], allowed);
        expect(
          response.headers['access-control-allow-methods'],
          contains('POST'),
        );
        expect(
          response.headers['access-control-allow-headers']?.toLowerCase(),
          contains('authorization'),
        );
        expect(response.headers['vary'], 'Origin');
      },
    );

    test(
      'the preflight short-circuit skips rate limiting entirely',
      () async {
        // A preflight carries no Authorization and must never be counted
        // against a rate-limit bucket a real request would then find empty.
        final rateLimited = buildHandler(
          db,
          signingSecret: 'test-secret',
          issuer: 'test',
          config: configWith(
            corsAllowedOrigins: {allowed},
            rateLimitEnabled: true,
            rateLimitBucketCapacity: 2,
          ),
        );

        for (var i = 0; i < 5; i++) {
          final response = await Future<Response>.value(
            rateLimited(
              Request(
                'OPTIONS',
                Uri.parse('http://logs.example.test/v1/auth/token'),
                headers: {
                  'origin': allowed,
                  'access-control-request-method': 'POST',
                },
              ),
            ),
          );
          expect(response.statusCode, 204, reason: 'preflight $i');
        }

        final loginResponse = await Future<Response>.value(
          rateLimited(
            Request(
              'POST',
              Uri.parse('http://logs.example.test/v1/auth/token'),
              body: 'grant_type=password&username=x&password=x',
              headers: {
                'origin': allowed,
                'content-type': 'application/x-www-form-urlencoded',
              },
            ),
          ),
        );
        expect(
          loginResponse.statusCode,
          isNot(429),
          reason: 'five preflights must not have spent the two-token bucket a '
              'real request still needs',
        );
      },
    );

    test('an origin outside the list gets nothing, even with CORS on',
        () async {
      final response = await get('http://elsewhere.test', path: '/healthz');
      expect(
        response.headers,
        isNot(contains('access-control-allow-origin')),
      );

      final preflightResponse = await preflight(
        'http://elsewhere.test',
        path: '/v1/logs',
      );
      expect(
        preflightResponse.statusCode,
        isNot(200),
        reason: 'unmatched origin — same as CORS being off entirely',
      );
      expect(
        preflightResponse.headers,
        isNot(contains('access-control-allow-origin')),
      );
    });
  });
}
