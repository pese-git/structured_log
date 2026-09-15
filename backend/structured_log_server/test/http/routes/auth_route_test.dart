import 'dart:convert';

import 'package:drift/native.dart';
import 'package:fpdart/fpdart.dart';
import 'package:shelf/shelf.dart';
import 'package:structured_log_server/src/auth/claims.dart';
import 'package:structured_log_server/src/auth/hashing.dart';
import 'package:structured_log_server/src/auth/token_service.dart';
import 'package:structured_log_server/src/http/routes/auth_route.dart';
import 'package:structured_log_server/src/rbac/authorizer.dart';
import 'package:structured_log_server/src/storage/database.dart';
import 'package:test/test.dart';

StructuredLogDatabase openInMemory() {
  return StructuredLogDatabase(
    NativeDatabase.memory(
      setup: (db) => db.execute('PRAGMA foreign_keys=ON;'),
    ),
  );
}

/// Returns whatever it is told to, so the route's rendering of every
/// [TokenError] can be exercised — including `reason`, which only the
/// not-yet-implemented email-verification flow produces
/// (`log-server-email-verification`).
class _StubTokenService implements TokenService {
  Either<TokenError, TokenPair> passwordResult;
  Either<TokenError, TokenPair> refreshResult;
  final revoked = <String>[];

  _StubTokenService({
    required this.passwordResult,
    required this.refreshResult,
  });

  @override
  Future<Either<TokenError, TokenPair>> passwordGrant({
    required String username,
    required String password,
  }) async =>
      passwordResult;

  @override
  Future<Either<TokenError, TokenPair>> refreshTokenGrant(String token) async =>
      refreshResult;

  @override
  Future<void> revoke(String presentedToken) async =>
      revoked.add(presentedToken);

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _pair = TokenPair(
  accessToken: 'access',
  refreshToken: 'refresh',
  accessTokenTtl: Duration(minutes: 15),
  refreshTokenTtl: Duration(days: 30),
);

Request form(String method, String body) {
  return Request(
    method,
    Uri.parse('http://x/v1/auth/token'),
    body: body,
    headers: {'content-type': 'application/x-www-form-urlencoded'},
  );
}

Future<Map<String, Object?>> decode(Response response) async {
  final text = await response.readAsString();
  return text.isEmpty ? const {} : jsonDecode(text) as Map<String, Object?>;
}

void main() {
  // `TokenService` is covered on its own; what lives only here is the
  // dispatch on `grant_type` and the RFC 6749 §5.2 rendering. That shape is
  // deliberately different from the general error envelope every other
  // endpoint uses (`log-server-api`), so a mix-up between the two has to
  // fail a test rather than reach a client.
  group('POST /v1/auth/token', () {
    late _StubTokenService service;
    late AuthRoutes routes;

    setUp(() {
      service = _StubTokenService(
        passwordResult: const Right(_pair),
        refreshResult: const Right(_pair),
      );
      routes = AuthRoutes(service);
    });

    test('a password grant returns the RFC 6749 §5.1 token response', () async {
      final response = await routes.router.call(
        form('POST', 'grant_type=password&username=u&password=p'),
      );

      expect(response.statusCode, 200);
      expect(response.headers['content-type'], contains('application/json'));
      expect(await decode(response), {
        'access_token': 'access',
        'token_type': 'Bearer',
        'expires_in': 900,
        'refresh_token': 'refresh',
        'refresh_expires_in': 2592000,
      });
    });

    test('a refresh grant returns the same shape', () async {
      final response = await routes.router.call(
        form('POST', 'grant_type=refresh_token&refresh_token=r'),
      );

      expect(response.statusCode, 200);
      expect((await decode(response))['access_token'], 'access');
    });

    test('an unknown grant_type is unsupported_grant_type', () async {
      final response = await routes.router
          .call(form('POST', 'grant_type=client_credentials'));

      expect(response.statusCode, 400);
      final body = await decode(response);
      expect(body['error'], 'unsupported_grant_type');
      expect(body['error_description'], contains('grant_type'));
    });

    test('a missing grant_type is unsupported_grant_type too', () async {
      final response = await routes.router.call(form('POST', ''));

      expect(response.statusCode, 400);
      expect((await decode(response))['error'], 'unsupported_grant_type');
    });

    test('a password grant without username or password is invalid_request',
        () async {
      for (final body in [
        'grant_type=password',
        'grant_type=password&username=u',
        'grant_type=password&password=p',
      ]) {
        final response = await routes.router.call(form('POST', body));

        expect(response.statusCode, 400, reason: body);
        expect(
          (await decode(response))['error'],
          'invalid_request',
          reason: body,
        );
      }
    });

    test('a refresh grant without a token is invalid_request', () async {
      final response =
          await routes.router.call(form('POST', 'grant_type=refresh_token'));

      expect(response.statusCode, 400);
      expect((await decode(response))['error'], 'invalid_request');
    });

    test('the service rejecting credentials renders invalid_grant', () async {
      service.passwordResult =
          const Left(TokenError(TokenErrorCode.invalidGrant));

      final response = await routes.router.call(
        form('POST', 'grant_type=password&username=u&password=wrong'),
      );

      expect(response.statusCode, 400);
      final body = await decode(response);
      expect(body['error'], 'invalid_grant');
      expect(body['error_description'], isNotEmpty);
      expect(body, isNot(contains('message')),
          reason: 'the general envelope must not leak into this endpoint');
      expect(body, isNot(contains('reason')),
          reason: 'the extension field appears only when the service sets it');
    });

    test('the service\'s reason extension is carried through', () async {
      // The one non-standard field this API adds on top of RFC 6749: an
      // unverified email is reported as a reason alongside invalid_grant
      // (`log-server-email-verification`).
      service.passwordResult = const Left(
        TokenError(TokenErrorCode.invalidGrant, reason: 'email_not_verified'),
      );

      final response = await routes.router.call(
        form('POST', 'grant_type=password&username=u&password=p'),
      );

      final body = await decode(response);
      expect(body['error'], 'invalid_grant');
      expect(body['reason'], 'email_not_verified');
    });

    test('every TokenErrorCode renders a distinct code and a description',
        () async {
      // Guards the switch from acquiring a case that falls through to
      // another's wording as new codes are added.
      const expected = {
        TokenErrorCode.invalidGrant: 'invalid_grant',
        TokenErrorCode.invalidRequest: 'invalid_request',
        TokenErrorCode.unsupportedGrantType: 'unsupported_grant_type',
      };
      expect(expected.keys, unorderedEquals(TokenErrorCode.values));

      final descriptions = <String>{};
      for (final entry in expected.entries) {
        service.passwordResult = Left(TokenError(entry.key));
        final body = await decode(
          await routes.router.call(
            form('POST', 'grant_type=password&username=u&password=p'),
          ),
        );

        expect(body['error'], entry.value);
        descriptions.add(body['error_description'] as String);
      }
      expect(descriptions, hasLength(expected.length));
    });
  });

  group('DELETE /v1/auth/token', () {
    late _StubTokenService service;
    late AuthRoutes routes;

    setUp(() {
      service = _StubTokenService(
        passwordResult: const Right(_pair),
        refreshResult: const Right(_pair),
      );
      routes = AuthRoutes(service);
    });

    test('revoking answers 200 with an empty body', () async {
      final response =
          await routes.router.call(form('DELETE', 'refresh_token=r'));

      expect(response.statusCode, 200);
      expect(await response.readAsString(), isEmpty);
      expect(service.revoked, ['r']);
    });

    test('an unknown token is still 200, to avoid enumeration', () async {
      // RFC 7009 §2.2: the endpoint must not reveal whether the presented
      // token existed. The service swallows that distinction, and the route
      // must not reintroduce it.
      final response = await routes.router
          .call(form('DELETE', 'refresh_token=never-issued'));

      expect(response.statusCode, 200);
      expect(service.revoked, ['never-issued']);
    });

    test('a missing refresh_token is invalid_request, and revokes nothing',
        () async {
      final response = await routes.router.call(form('DELETE', ''));

      expect(response.statusCode, 400);
      expect((await decode(response))['error'], 'invalid_request');
      expect(service.revoked, isEmpty);
    });
  });

  group('against the real TokenService', () {
    late StructuredLogDatabase db;
    late AuthRoutes routes;

    setUp(() async {
      db = openInMemory();
      final service = TokenService(
        db,
        ClaimsResolver(db, Authorizer(db)),
        signingSecret: 'test-secret',
        issuer: 'test',
      );
      routes = AuthRoutes(service);
      await db.into(db.users).insert(
            UsersCompanion.insert(
              username: 'alice',
              passwordHash: hashPassword('pw'),
            ),
          );
    });
    tearDown(() => db.close());

    test('issues a usable pair and revokes it again', () async {
      // The stub above pins the rendering; this pins that the rendering is
      // fed by values the real service actually produces.
      final issued = await decode(
        await routes.router.call(
          form('POST', 'grant_type=password&username=alice&password=pw'),
        ),
      );
      expect(issued['access_token'], isA<String>());
      expect(issued['expires_in'], isA<int>());

      final refreshToken = issued['refresh_token'] as String;
      expect(
        (await routes.router
                .call(form('DELETE', 'refresh_token=$refreshToken')))
            .statusCode,
        200,
      );

      final reuse = await routes.router.call(
        form('POST', 'grant_type=refresh_token&refresh_token=$refreshToken'),
      );
      expect(reuse.statusCode, 400);
      expect((await decode(reuse))['error'], 'invalid_grant');
    });

    test('a wrong password is invalid_grant', () async {
      final response = await routes.router.call(
        form('POST', 'grant_type=password&username=alice&password=nope'),
      );

      expect(response.statusCode, 400);
      expect((await decode(response))['error'], 'invalid_grant');
    });
  });

  group('a malformed body is refused, not crashed into', () {
    // Both token endpoints are pre-auth: whatever arrives here is input nobody
    // controls. Uri.splitQueryString throws on illegal percent encoding, and
    // an uncaught throw meant 500 plus a stack trace in the server log for
    // anything a caller felt like sending.
    test('POST answers 400 invalid_request', () async {
      final routes = AuthRoutes(
        _StubTokenService(
          passwordResult: const Right(_pair),
          refreshResult: const Right(_pair),
        ),
      );
      final response = await routes.router.call(
        form('POST', 'grant_type=password&username=a&password=%zz'),
      );

      expect(response.statusCode, 400);
      expect(await decode(response), containsPair('error', 'invalid_request'));
    });

    test('DELETE answers 400 invalid_request', () async {
      final routes = AuthRoutes(
        _StubTokenService(
          passwordResult: const Right(_pair),
          refreshResult: const Right(_pair),
        ),
      );
      final response = await routes.router.call(
        form('DELETE', 'refresh_token=%zz'),
      );

      expect(response.statusCode, 400);
      expect(await decode(response), containsPair('error', 'invalid_request'));
    });
  });
}
