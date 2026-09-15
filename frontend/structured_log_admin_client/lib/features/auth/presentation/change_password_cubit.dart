import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../application/change_password.dart';
import '../domain/auth_failure.dart';

part 'change_password_cubit.freezed.dart';

/// What the change-password form is doing.
///
/// A data class, like the login screen's: submitting, having failed, and
/// having succeeded are conditions of one form rather than separate shapes.
@freezed
abstract class ChangePasswordState with _$ChangePasswordState {
  const factory ChangePasswordState({
    @Default(false) bool submitting,
    @Default(false) bool changed,

    /// Set when the two new-password fields disagree. Checked here rather
    /// than at the server, which is only ever sent one of them.
    @Default(false) bool mismatch,

    AuthFailure? failure,

    /// Who is signed in, for the line the screen shows above "выйти".
    String? username,
  }) = _ChangePasswordState;

  const ChangePasswordState._();

  /// Nothing to submit while a field is empty or the two copies disagree.
  bool get canSubmit => !submitting && !changed;
}

/// Drives both ways into `POST /v1/auth/change-password`: the screen the
/// server forces after a temporary password, and the voluntary one in
/// settings. The difference is what the caller does with [ChangePasswordState.changed],
/// not what happens here.
class ChangePasswordCubit extends Cubit<ChangePasswordState> {
  final ChangePassword _changePassword;
  final CurrentUsername _currentUsername;

  ChangePasswordCubit({
    required ChangePassword changePassword,
    required CurrentUsername currentUsername,
  }) : _changePassword = changePassword,
       _currentUsername = currentUsername,
       super(const ChangePasswordState());

  Future<void> loadUsername() async {
    final username = await _currentUsername();
    if (isClosed || username == null) return;
    emit(state.copyWith(username: username));
  }

  Future<void> submit({
    required String currentPassword,
    required String newPassword,
    required String repeatedPassword,
  }) async {
    if (!state.canSubmit) return;

    if (newPassword != repeatedPassword) {
      // Not sent: the server has no way to tell the two apart, and a round
      // trip to learn what the form already knows would also spend one of the
      // rate limiter's attempts.
      emit(state.copyWith(mismatch: true, failure: null));
      return;
    }

    emit(state.copyWith(submitting: true, mismatch: false, failure: null));
    final result = await _changePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
    if (isClosed) return;

    result.match(
      (failure) => emit(state.copyWith(submitting: false, failure: failure)),
      (_) => emit(state.copyWith(submitting: false, changed: true)),
    );
  }
}
