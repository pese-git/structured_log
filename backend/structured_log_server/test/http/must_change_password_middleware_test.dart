import 'package:shelf/shelf.dart';
import 'package:structured_log_server/src/auth/identity_provider.dart';
import 'package:structured_log_server/src/http/must_change_password_middleware.dart';
import 'package:test/test.dart';

Request _withIdentity(VerifiedIdentity identity) {
  return Request(
    'GET',
    Uri.parse('http://x/y'),
    context: {'structured_log_server.verifiedIdentity': identity},
  );
}

void main() {
  test(
      'a request from an account that must change its password is rejected with 403',
      () async {
    final handler = mustChangePasswordMiddleware()((req) => Response.ok('ok'));
    final response = await handler(
      _withIdentity(
        const VerifiedIdentity(
          userId: 1,
          username: 'alice',
          mustChangePassword: true,
        ),
      ),
    );
    expect(response.statusCode, 403);
  });

  test(
      'a request from an account with no pending password change passes through',
      () async {
    final handler = mustChangePasswordMiddleware()((req) => Response.ok('ok'));
    final response = await handler(
      _withIdentity(
        const VerifiedIdentity(userId: 1, username: 'alice'),
      ),
    );
    expect(response.statusCode, 200);
  });
}
