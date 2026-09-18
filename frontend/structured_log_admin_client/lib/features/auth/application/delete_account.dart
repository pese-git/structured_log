import 'package:dio/dio.dart';
import 'package:fpdart/fpdart.dart';
import 'package:structured_log/structured_log.dart';

import '../../../shared/api/api_client.dart';
import '../../../shared/api/api_failure.dart';
import '../../../shared/api/dto/auth_dto.dart';
import '../../../shared/api/failure_mapper.dart';

/// Permanently deletes the signed-in account itself.
///
/// Not on `AuthRepository`, on purpose: every other method there answers in
/// `AuthFailure`, the RFC 6749 shape `POST /v1/auth/token` alone uses
/// (`auth_failure.dart`). `DELETE /v1/users/me` answers in the API's general
/// `{"error", "message", "details"}` envelope instead — the same one
/// `sole_group_owner` and its `blocking_groups` payload already have a home
/// in (`ApiFailure`) — so this goes straight through that, the way
/// `ManageUsers` does for the admin deletion path it shares a server-side
/// implementation with.
class DeleteAccount {
  final ApiClient _api;
  final BoundLogger _log;

  DeleteAccount(this._api, BoundLogger logger)
    : _log = logger.bind({'feature': 'auth'});

  Future<Either<ApiFailure, Unit>> call(String password) async {
    try {
      await _api.auth.deleteMe(DeleteAccountRequestDto(password: password));
      // Neither the password nor anything else about the account is logged
      // (decision 48) — only that it happened.
      _log.info('auth.account_deleted');
      return right(unit);
    } on DioException catch (error) {
      return left(mapDioException(error));
    }
  }
}
