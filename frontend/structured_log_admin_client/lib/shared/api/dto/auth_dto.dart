import 'package:freezed_annotation/freezed_annotation.dart';

part 'auth_dto.freezed.dart';
part 'auth_dto.g.dart';

/// The body of a successful `POST /v1/auth/token`, for either grant.
@freezed
abstract class TokenResponseDto with _$TokenResponseDto {
  const factory TokenResponseDto({
    @JsonKey(name: 'access_token') required String accessToken,
    @JsonKey(name: 'refresh_token') required String refreshToken,
    @JsonKey(name: 'token_type') required String tokenType,

    /// Lifetime of the access token in seconds. The client does not schedule
    /// a refresh off it — the 401 interceptor is what actually renews — but a
    /// screen may show how long a session has left.
    @JsonKey(name: 'expires_in') required int expiresIn,
  }) = _TokenResponseDto;

  factory TokenResponseDto.fromJson(Map<String, dynamic> json) =>
      _$TokenResponseDtoFromJson(json);
}

/// `POST /v1/auth/change-password`.
@freezed
abstract class ChangePasswordRequestDto with _$ChangePasswordRequestDto {
  const factory ChangePasswordRequestDto({
    @JsonKey(name: 'current_password') required String currentPassword,
    @JsonKey(name: 'new_password') required String newPassword,

    /// Leaves every other device signed in. Sent as the exception, because on
    /// the server the *absence* of it means "sign them out" — the safe
    /// reading has to be the one a caller gets by saying nothing.
    @JsonKey(name: 'keep_other_sessions') required bool keepOtherSessions,

    /// The caller's own refresh token, so the sweep can spare this session.
    /// The server has no other way to recognise it: this endpoint
    /// authenticates with an access token, and stored refresh tokens are
    /// hashes that say nothing about whose device they are.
    ///
    /// `includeIfNull: false` — an absent field and a `null` one mean the same
    /// thing to the server (sweep everything, this session included), and
    /// putting a null on the wire for a credential reads like a value that
    /// went missing.
    @JsonKey(name: 'current_refresh_token', includeIfNull: false)
    String? currentRefreshToken,
  }) = _ChangePasswordRequestDto;

  factory ChangePasswordRequestDto.fromJson(Map<String, dynamic> json) =>
      _$ChangePasswordRequestDtoFromJson(json);
}

/// `DELETE /v1/users/me` — the caller's own current password, confirming
/// they mean it (`DeleteAccountDialog.dc.html`). Unlike the admin path
/// (`DELETE /v1/users/{id}`), nobody else has confirmed this is wanted.
@freezed
abstract class DeleteAccountRequestDto with _$DeleteAccountRequestDto {
  const factory DeleteAccountRequestDto({required String password}) =
      _DeleteAccountRequestDto;

  factory DeleteAccountRequestDto.fromJson(Map<String, dynamic> json) =>
      _$DeleteAccountRequestDtoFromJson(json);
}
