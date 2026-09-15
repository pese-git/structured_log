import 'package:freezed_annotation/freezed_annotation.dart';

part 'api_failure.freezed.dart';

/// Every outcome a request can have other than success.
///
/// These are expected alternatives, not defects: a refused sign-in, a quota
/// that is full, a role that may not do this. They travel as the left side of
/// an `Either` and the caller has to say what it does with each
/// (design.md decision 33). A broken invariant still throws.
///
/// The server states its errors as `{"error": code, "message": ..., "details":
/// {...}}`, so the code travels with the failure rather than being flattened
/// into a string — screens key off it: `must_change_password` opens the forced
/// change screen, `email_not_verified` offers to resend.
@freezed
sealed class ApiFailure with _$ApiFailure {
  /// The request never reached the server, or the answer never came back.
  const factory ApiFailure.network({String? message}) = NetworkFailure;

  /// 401 — and the refresh that would have fixed it did not.
  const factory ApiFailure.unauthorized({
    required String code,
    String? message,
  }) = UnauthorizedFailure;

  /// 403 — the role may not do this, or a gate stands in the way.
  const factory ApiFailure.forbidden({
    required String code,
    String? message,
    Map<String, dynamic>? details,
  }) = ForbiddenFailure;

  const factory ApiFailure.notFound({required String code, String? message}) =
      NotFoundFailure;

  /// 409 — a unique name taken, the last owner of a group, a quota exhausted.
  const factory ApiFailure.conflict({
    required String code,
    String? message,
    Map<String, dynamic>? details,
  }) = ConflictFailure;

  /// 400 — the request itself was wrong; `details` names the field.
  const factory ApiFailure.invalidRequest({
    required String code,
    String? message,
    Map<String, dynamic>? details,
  }) = InvalidRequestFailure;

  /// 429. Carries what `Retry-After` said, so a screen can count down instead
  /// of guessing — and nothing retries on its own (decision 45).
  const factory ApiFailure.rateLimited({
    required Duration retryAfter,
    String? message,
  }) = RateLimitedFailure;

  /// 5xx, or a status this client has no meaning for.
  const factory ApiFailure.server({
    required int statusCode,
    String? code,
    String? message,
  }) = ServerFailure;
}
