import 'package:freezed_annotation/freezed_annotation.dart';

import '../domain/auth_failure.dart';

part 'login_state.freezed.dart';

/// What the login screen is showing.
///
/// A data class rather than a union: a form is one thing in several
/// simultaneous conditions — submitting, carrying an error, counting down —
/// not one of several mutually exclusive shapes. [AuthFailure] stays a union,
/// because the *reason* genuinely is one of a closed set.
@freezed
abstract class LoginState with _$LoginState {
  const factory LoginState({
    @Default(false) bool submitting,

    /// Set once the tokens are stored. The shell watches this and moves on;
    /// the screen itself never navigates.
    @Default(false) bool signedIn,

    /// Why the last attempt failed, or `null` before the first one.
    AuthFailure? failure,

    /// Remaining wait after a 429, ticked down once a second. Submission is
    /// blocked while it is above zero.
    @Default(Duration.zero) Duration retryAfter,
  }) = _LoginState;

  const LoginState._();

  /// The form may be sent: nothing in flight, and no limiter still counting.
  bool get canSubmit => !submitting && retryAfter == Duration.zero;
}
