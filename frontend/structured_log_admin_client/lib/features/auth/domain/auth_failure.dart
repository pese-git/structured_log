import 'package:freezed_annotation/freezed_annotation.dart';

part 'auth_failure.freezed.dart';

/// Why signing in, or signing out, did not work.
///
/// Separate from the shared `ApiFailure` on purpose: `POST /v1/auth/token` is
/// the one endpoint that answers in the RFC 6749 shape
/// (`{error, error_description, reason?}`) rather than the API's general
/// envelope, and `reason` is the extension this server defines on top of it.
/// Flattening that into the shared type would lose the one field the login
/// screen needs to tell "wrong password" from "confirm your email first".
@freezed
sealed class AuthFailure with _$AuthFailure {
  /// `invalid_grant` with no `reason` — wrong username or password.
  ///
  /// Which of the two is deliberately not said, by the server and so by the
  /// screen: naming it would let anyone enumerate accounts.
  const factory AuthFailure.invalidCredentials() = InvalidCredentialsFailure;

  /// `invalid_grant` with `reason: email_not_verified`. A different situation
  /// with a different way out, so it gets its own message and its own action.
  const factory AuthFailure.emailNotVerified() = EmailNotVerifiedFailure;

  /// 429. [retryAfter] comes from the header; the screen counts it down and
  /// nothing retries by itself.
  const factory AuthFailure.rateLimited(Duration retryAfter) =
      RateLimitedAuthFailure;

  /// The server was never reached.
  ///
  /// [message] is **diagnostic only** — it carries whatever the HTTP client
  /// said, which is English, long, and about XMLHttpRequest and CORS. It
  /// belongs in the log; the screen says something a person can act on.
  const factory AuthFailure.network({String? message}) = NetworkAuthFailure;

  /// Anything else — a 5xx, or a shape this client does not recognise.
  ///
  /// [message] is diagnostic only, for the same reason as above: it is the
  /// server's `error_description`, written for a developer reading a log.
  const factory AuthFailure.unexpected({String? message}) =
      UnexpectedAuthFailure;
}
