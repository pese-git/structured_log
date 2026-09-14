import 'dart:convert';

import 'package:shelf/shelf.dart';

import '../../auth/token_service.dart';

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

Map<String, Object?> _pairJson(TokenPair pair) => {
      'access_token': pair.accessToken,
      'token_type': 'Bearer',
      'expires_in': pair.accessTokenTtl.inSeconds,
      'refresh_token': pair.refreshToken,
      'refresh_expires_in': pair.refreshTokenTtl.inSeconds,
    };

/// `POST /v1/auth/token` — form-encoded, `grant_type=password` or
/// `grant_type=refresh_token` (`log-server-auth`, RFC 6749).
Future<Response> issueToken(TokenService tokenService, Request request) async {
  final form = Uri.splitQueryString(await request.readAsString());
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
      final result = await tokenService.passwordGrant(
        username: username,
        password: password,
      );
      return result.match(
        (error) => _rfc6749Error(400, error),
        (pair) => Response(
          200,
          body: jsonEncode(_pairJson(pair)),
          headers: {'content-type': 'application/json'},
        ),
      );

    case 'refresh_token':
      final refreshToken = form['refresh_token'];
      if (refreshToken == null) {
        return _rfc6749Error(
          400,
          const TokenError(TokenErrorCode.invalidRequest),
        );
      }
      final result = await tokenService.refreshTokenGrant(refreshToken);
      return result.match(
        (error) => _rfc6749Error(400, error),
        (pair) => Response(
          200,
          body: jsonEncode(_pairJson(pair)),
          headers: {'content-type': 'application/json'},
        ),
      );

    default:
      return _rfc6749Error(
        400,
        const TokenError(TokenErrorCode.unsupportedGrantType),
      );
  }
}

/// `DELETE /v1/auth/token` — always `200` with an empty body once
/// `refresh_token` is present, regardless of whether it was valid
/// (RFC 7009 §2.2, anti-enumeration).
Future<Response> revokeToken(TokenService tokenService, Request request) async {
  final form = Uri.splitQueryString(await request.readAsString());
  final refreshToken = form['refresh_token'];
  if (refreshToken == null) {
    return _rfc6749Error(400, const TokenError(TokenErrorCode.invalidRequest));
  }
  await tokenService.revoke(refreshToken);
  return Response(200, body: '');
}
