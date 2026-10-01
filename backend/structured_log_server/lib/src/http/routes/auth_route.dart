import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../auth/token_service.dart';
import '../rate_limit/client_ip.dart';
import '../refresh_cookie.dart';
import '../request_helpers.dart';
import '../rate_limit_middleware.dart';

part 'auth_route.g.dart';

/// Renders a [TokenError] as the RFC 6749 §5.2 JSON body — the one place
/// in this API that doesn't use the general error envelope
/// (`log-server-api`/`design.md` decision 10).
Response _rfc6749Error(int statusCode, TokenError error) {
  final body = <String, Object?>{
    'error': _errorCodeName(error.code),
    'error_description': _description(error.code),
  };
  if (error.reason != null) body['reason'] = error.reason;
  return Response(
    statusCode,
    body: jsonEncode(body),
    headers: {'content-type': 'application/json'},
  );
}

String _errorCodeName(TokenErrorCode code) {
  switch (code) {
    case TokenErrorCode.invalidGrant:
      return 'invalid_grant';
    case TokenErrorCode.invalidRequest:
      return 'invalid_request';
    case TokenErrorCode.unsupportedGrantType:
      return 'unsupported_grant_type';
  }
}

String _description(TokenErrorCode code) {
  switch (code) {
    case TokenErrorCode.invalidGrant:
      return 'The provided credentials or token are invalid.';
    case TokenErrorCode.invalidRequest:
      return 'A required field is missing.';
    case TokenErrorCode.unsupportedGrantType:
      return 'grant_type must be "password" or "refresh_token".';
  }
}

/// The RFC 6749 §5.1 body, plus one field of this server's own.
///
/// `refresh_token` is present whatever [cookieSet] says: the cookie is an
/// addition, so a caller that keeps none reads the body exactly as it did
/// before cookies existed. `refresh_token_cookie_set` is what tells a browser
/// client it may drop its copy — the client is told the mode rather than
/// configured with it, so the two can never disagree
/// (`add-refresh-token-cookie/design.md`, decision 2).
///
/// The name describes what the server did, not where the token is: under
/// `auto` a cookie is set for a caller with no `Origin` at all, and calling
/// the field `refresh_token_in_cookie` would be untrue for exactly those
/// callers who cannot use it.
Map<String, Object?> _pairJson(TokenPair pair, {required bool cookieSet}) => {
  'access_token': pair.accessToken,
  'token_type': 'Bearer',
  'expires_in': pair.accessTokenTtl.inSeconds,
  'refresh_token': pair.refreshToken,
  'refresh_expires_in': pair.refreshTokenTtl.inSeconds,
  'refresh_token_cookie_set': cookieSet,
};

/// The form body, or `null` when it is malformed or over the cap. Public and
/// unauthenticated, so the cap is enforced while reading rather than after.
Future<Map<String, String>?> _readForm(Request request) async {
  try {
    return tryParseFormBody(await readBodyCapped(request, maxSmallBodyBytes));
  } on BodyTooLargeException {
    return null;
  }
}

/// The token endpoints. Public: [TokenService] checks the credentials these
/// carry in the body, so no principal is required of the request itself.
class AuthRoutes {
  final TokenService _tokenService;

  /// How many proxies sit in front, so the address in the audit record is the
  /// caller's rather than the last hop's. Same count the rate limiter uses —
  /// getting it wrong there lets an address be forged, and getting it wrong
  /// here writes a forged address into a journal kept for years.
  final int _trustedProxyHops;

  /// Whether a successful grant also hands the refresh token to the browser
  /// as an `HttpOnly` cookie, and the origins the operator declared foreign.
  final RefreshCookieMode _refreshTokenCookie;
  final Set<String> _corsAllowedOrigins;

  AuthRoutes(
    this._tokenService, {
    int trustedProxyHops = 0,
    RefreshCookieMode refreshTokenCookie = RefreshCookieMode.off,
    Set<String> corsAllowedOrigins = const {},
  }) : _trustedProxyHops = trustedProxyHops,
       _refreshTokenCookie = refreshTokenCookie,
       _corsAllowedOrigins = corsAllowedOrigins;

  /// The successful token response, carrying the cookie when this request's
  /// origin is one that should get it.
  Response _pairResponse(Request request, TokenPair pair) {
    final setsCookie = shouldSetRefreshCookie(
      _refreshTokenCookie,
      origin: request.headers['origin'],
      allowedOrigins: _corsAllowedOrigins,
    );
    return Response(
      200,
      body: jsonEncode(_pairJson(pair, cookieSet: setsCookie)),
      headers: {
        'content-type': 'application/json',
        if (setsCookie)
          'set-cookie': buildRefreshCookie(
            pair.refreshToken,
            maxAge: pair.refreshTokenTtl,
          ),
      },
    );
  }

  Router get router => _$AuthRoutesRouter(this);

  /// Form-encoded, `grant_type=password` or `grant_type=refresh_token`
  /// (`log-server-auth`, RFC 6749).
  @Route.post('/v1/auth/token')
  Future<Response> issueToken(Request request) async {
    final form = await _readForm(request);
    if (form == null) {
      return _rfc6749Error(
        400,
        const TokenError(TokenErrorCode.invalidRequest),
      );
    }
    final grantType = form['grant_type'];

    switch (grantType) {
      case 'password':
        final username = form['username'];
        final password = form['password'];
        if (username == null || password == null) {
          return _rfc6749Error(
            400,
            const TokenError(TokenErrorCode.invalidRequest),
          );
        }
        // The subject half of the limiter, checked before the password is:
        // a throttled attempt must not verify credentials at all, even
        // correct ones (`log-server-rate-limit`).
        final attempt = request.rateLimitAttempt;
        await attempt.requireSubject(username);

        final result = await _tokenService.passwordGrant(
          username: username,
          password: password,
          clientIp: resolveClientIp(
            request,
            trustedProxyHops: _trustedProxyHops,
          ),
          userAgent: request.headers['user-agent'],
        );
        return result.match(
          (error) {
            attempt.failed();
            return _rfc6749Error(400, error);
          },
          (pair) {
            attempt.succeeded();
            return _pairResponse(request, pair);
          },
        );

      case 'refresh_token':
        // The field first, the cookie only in its absence: the field is the
        // caller naming a token, the cookie is what the browser attached by
        // itself. On `DELETE` below the same order decides whose session ends.
        final refreshToken =
            form['refresh_token'] ?? refreshCookieOf(request.headers['cookie']);
        if (refreshToken == null) {
          return _rfc6749Error(
            400,
            const TokenError(TokenErrorCode.invalidRequest),
          );
        }
        final result = await _tokenService.refreshTokenGrant(refreshToken);
        return result.match(
          (error) => _rfc6749Error(400, error),
          (pair) => _pairResponse(request, pair),
        );

      default:
        return _rfc6749Error(
          400,
          const TokenError(TokenErrorCode.unsupportedGrantType),
        );
    }
  }

  /// Always `200` with an empty body once `refresh_token` is present,
  /// regardless of whether it was valid (RFC 7009 §2.2, anti-enumeration).
  @Route.delete('/v1/auth/token')
  Future<Response> revokeToken(Request request) async {
    final form = await _readForm(request);
    if (form == null) {
      return _rfc6749Error(
        400,
        const TokenError(TokenErrorCode.invalidRequest),
      );
    }
    final fromCookie = refreshCookieOf(request.headers['cookie']);
    final refreshToken = form['refresh_token'] ?? fromCookie;
    if (refreshToken == null) {
      return _rfc6749Error(
        400,
        const TokenError(TokenErrorCode.invalidRequest),
      );
    }
    await _tokenService.revoke(
      refreshToken,
      clientIp: resolveClientIp(request, trustedProxyHops: _trustedProxyHops),
      userAgent: request.headers['user-agent'],
    );
    // Cleared when the cookie is what we just revoked, and then regardless of
    // whether that token was live: RFC 7009 §2.2 forbids the response from
    // differing by validity, and clearing only on a hit would make it differ.
    // A caller that named a token in the form is revoking something other than
    // the browser's own session, so its cookie is left alone.
    final clears = form['refresh_token'] == null && fromCookie != null;
    return Response(
      200,
      body: '',
      headers: {if (clears) 'set-cookie': clearRefreshCookie()},
    );
  }
}
