import 'package:flutter/foundation.dart';

import '../auth/token_pair.dart';
import 'dto/auth_dto.dart';

/// Whether this platform keeps cookies on the client's behalf.
///
/// Only a browser does. `dio` on the Dart VM stores none, so a caller there
/// that believed `refresh_token_cookie_set` and dropped its copy would be
/// left with no way to renew at all — the cookie it was told about exists
/// only in a response header nobody kept.
const platformHoldsCookies = kIsWeb;

/// The session to hold on to, out of what the token endpoint answered.
///
/// The server's `refresh_token_cookie_set` is a fact about the server, not
/// about the caller: it says a `Set-Cookie` went out, not that anyone caught
/// it. Both halves have to be true before the client may let go of the token
/// in the body.
///
/// This is why the field is named for what the server did. Under `auto` a
/// caller with no `Origin` — `curl`, a script, `packages/e2e` — is sent a
/// cookie it will never use, and a client that read the field as "the token
/// is in a cookie" would conclude it had a session it cannot renew. Found
/// exactly that way: `packages/e2e` broke against a default server the moment
/// the client started honouring the field.
TokenPair sessionFrom(TokenResponseDto response) => TokenPair.fromGrant(
  accessToken: response.accessToken,
  refreshToken: response.refreshToken,
  cookieSet: response.refreshTokenCookieSet && platformHoldsCookies,
);
