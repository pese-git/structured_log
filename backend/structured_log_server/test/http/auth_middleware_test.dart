import 'package:shelf/shelf.dart';
import 'package:structured_log_server/src/auth/identity_provider.dart';
import 'package:structured_log_server/src/http/auth_middleware.dart';
import 'package:test/test.dart';

class _FakeIdentityProvider implements IdentityProvider {
  final VerifiedIdentity? Function(String) _verify;
  _FakeIdentityProvider(this._verify);

  @override
  Future<VerifiedIdentity?> verifyAccessToken(String bearerToken) async {
    return _verify(bearerToken);
  }
}

void main() {
  test('a request without an Authorization header is rejected with 401',
      () async {
    final handler = const Pipeline()
        .addMiddleware(authMiddleware(_FakeIdentityProvider((_) => null)))
        .addHandler((req) => Response.ok('ok'));

    final response = await handler(Request('GET', Uri.parse('http://x/y')));
    expect(response.statusCode, 401);
  });

  test('a non-Bearer Authorization header is rejected with 401', () async {
    final handler = const Pipeline()
        .addMiddleware(authMiddleware(_FakeIdentityProvider((_) => null)))
        .addHandler((req) => Response.ok('ok'));

    final response = await handler(
      Request(
        'GET',
        Uri.parse('http://x/y'),
        headers: {'authorization': 'Basic abc'},
      ),
    );
    expect(response.statusCode, 401);
  });

  test('a token the provider rejects is rejected with 401', () async {
    final handler = const Pipeline()
        .addMiddleware(authMiddleware(_FakeIdentityProvider((_) => null)))
        .addHandler((req) => Response.ok('ok'));

    final response = await handler(
      Request(
        'GET',
        Uri.parse('http://x/y'),
        headers: {'authorization': 'Bearer bad-token'},
      ),
    );
    expect(response.statusCode, 401);
  });

  test(
      'a token the provider accepts reaches the inner handler with the identity attached',
      () async {
    const identity = VerifiedIdentity(userId: 42, username: 'alice', roles: []);
    late VerifiedIdentity seenByHandler;

    final handler = const Pipeline()
        .addMiddleware(
      authMiddleware(
        _FakeIdentityProvider(
            (token) => token == 'good-token' ? identity : null),
      ),
    )
        .addHandler((req) {
      seenByHandler = req.verifiedIdentity;
      return Response.ok('ok');
    });

    final response = await handler(
      Request(
        'GET',
        Uri.parse('http://x/y'),
        headers: {'authorization': 'Bearer good-token'},
      ),
    );

    expect(response.statusCode, 200);
    expect(seenByHandler.userId, 42);
    expect(seenByHandler.username, 'alice');
  });
}
