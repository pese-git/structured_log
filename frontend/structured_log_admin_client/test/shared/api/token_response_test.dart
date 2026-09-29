import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log_admin_client/shared/api/dto/auth_dto.dart';
import 'package:structured_log_admin_client/shared/api/token_response.dart';

TokenResponseDto _response({required bool cookieSet}) => TokenResponseDto(
  accessToken: 'a',
  refreshToken: 'r',
  tokenType: 'Bearer',
  expiresIn: 900,
  refreshTokenCookieSet: cookieSet,
);

void main() {
  test('a platform without cookies keeps the token the body carried', () {
    // The server saying it set a cookie is a fact about the server, not about
    // the caller. `flutter test` and `packages/e2e` run on the VM, where dio
    // stores no cookies — dropping the copy there would leave the session
    // with no way to renew at all.
    expect(sessionFrom(_response(cookieSet: true)).refreshToken, 'r');
  });

  test('and keeps it when no cookie was set either', () {
    expect(sessionFrom(_response(cookieSet: false)).refreshToken, 'r');
  });

  test('the platform question is asked, not assumed', () {
    // Pins which side of the conditional import this run is on, so the test
    // above cannot pass for the wrong reason on some future host.
    expect(platformHoldsCookies, isFalse);
  });
}
