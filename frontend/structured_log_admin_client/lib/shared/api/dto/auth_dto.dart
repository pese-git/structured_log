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
  }) = _ChangePasswordRequestDto;

  factory ChangePasswordRequestDto.fromJson(Map<String, dynamic> json) =>
      _$ChangePasswordRequestDtoFromJson(json);
}
