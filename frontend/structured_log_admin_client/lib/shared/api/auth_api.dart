import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import 'dto/auth_dto.dart';

part 'auth_api.g.dart';

/// `/v1/auth/*`.
///
/// The token endpoints are form-encoded, not JSON — they follow RFC 6749, so
/// the grant travels as `grant_type` in a form body.
@RestApi()
abstract class AuthApi {
  factory AuthApi(Dio dio, {String baseUrl}) = _AuthApi;

  /// The two grants the server accepts. Passed explicitly rather than
  /// defaulted, because a method that quietly sent the wrong one would fail
  /// as `unsupported_grant_type` far from where the mistake was made.
  static const passwordGrant = 'password';
  static const refreshGrant = 'refresh_token';

  @POST('/v1/auth/token')
  @FormUrlEncoded()
  Future<TokenResponseDto> signIn(
    @Field('grant_type') String grantType,
    @Field('username') String username,
    @Field('password') String password,
  );

  @POST('/v1/auth/token')
  @FormUrlEncoded()
  Future<TokenResponseDto> refresh(
    @Field('grant_type') String grantType,
    @Field('refresh_token') String refreshToken,
  );

  /// Answers 200 whether or not the token was valid, so a caller learns
  /// nothing about tokens it does not hold. Sign-out clears the local session
  /// regardless of what this returns, including a network error
  /// (`specs/admin-client-auth`).
  @DELETE('/v1/auth/token')
  @FormUrlEncoded()
  Future<void> signOut(@Field('refresh_token') String refreshToken);

  /// Also the way out of the forced-change gate: on success the server stops
  /// answering `403 must_change_password`.
  @POST('/v1/auth/change-password')
  Future<void> changePassword(@Body() ChangePasswordRequestDto body);

  /// `/v1/users/me`, not `/v1/auth/*` — kept here anyway rather than in
  /// `UsersApi`, which every one of its other methods restricts to `admin`
  /// (`users_api.dart`). This one is self-service, over the caller's own
  /// account, the same shape as [changePassword] above it.
  ///
  /// `204` on success. `409 sole_group_owner` if the account is the last
  /// owner of a group — same conflict and payload shape `UsersApi.delete`
  /// answers with, since both share the server's one deletion path.
  @DELETE('/v1/users/me')
  Future<void> deleteMe(@Body() DeleteAccountRequestDto body);
}
