import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../application/sign_in.dart';
import '../domain/auth_failure.dart';
import 'login_state.dart';

/// The login screen's state (design.md decision 36).
///
/// Holds no `dio`, no storage and no navigation — it calls [SignIn] and
/// reports what came back. Whoever hosts the screen decides what
/// `signedIn` means for the route.
class LoginCubit extends Cubit<LoginState> {
  final SignIn _signIn;

  /// Counts a rate limit down. Cancelled on close so a disposed screen does
  /// not keep a timer alive.
  Timer? _countdown;

  LoginCubit(this._signIn) : super(const LoginState());

  Future<void> submit({
    required String username,
    required String password,
  }) async {
    if (!state.canSubmit) return;
    // Clearing the previous failure as the request goes out: leaving it on
    // screen next to a spinner reads as a fresh rejection.
    emit(state.copyWith(submitting: true, failure: null));

    final result = await _signIn(username: username, password: password);
    if (isClosed) return;

    result.match((failure) {
      emit(state.copyWith(submitting: false, failure: failure));
      if (failure is RateLimitedAuthFailure) {
        _startCountdown(failure.retryAfter);
      }
    }, (_) => emit(state.copyWith(submitting: false, signedIn: true)));
  }

  /// Dismisses the message — called when either field is edited, so the error
  /// belongs to the attempt that produced it and not to what is being typed
  /// now. A countdown is not cleared: typing does not appease a limiter.
  void clearFailure() {
    if (state.failure == null || state.failure is RateLimitedAuthFailure) {
      return;
    }
    emit(state.copyWith(failure: null));
  }

  void _startCountdown(Duration retryAfter) {
    _countdown?.cancel();
    emit(state.copyWith(retryAfter: retryAfter));
    _countdown = Timer.periodic(const Duration(seconds: 1), (timer) {
      final left = state.retryAfter - const Duration(seconds: 1);
      if (left <= Duration.zero) {
        timer.cancel();
        // The failure goes with the countdown: a message saying "wait" that
        // outlives the wait is just wrong.
        emit(state.copyWith(retryAfter: Duration.zero, failure: null));
      } else {
        emit(state.copyWith(retryAfter: left));
      }
    });
  }

  @override
  Future<void> close() {
    _countdown?.cancel();
    return super.close();
  }
}
