import 'package:dio/dio.dart';
import 'package:fpdart/fpdart.dart';

import '../../../shared/api/api_client.dart';
import '../../../shared/api/api_failure.dart';
import '../../../shared/api/dto/user_dto.dart';
import '../../../shared/api/failure_mapper.dart';
import '../domain/users_repository.dart';

class UsersRepositoryImpl implements UsersRepository {
  final ApiClient _api;

  const UsersRepositoryImpl(this._api);

  @override
  Future<Either<ApiFailure, UserPageDto>> firstPage({int? limit}) =>
      _attempt(() => _api.users.list(limit: limit));

  @override
  Future<Either<ApiFailure, UserPageDto>> nextPage({
    required String cursor,
    int? limit,
  }) => _attempt(() => _api.users.list(cursor: cursor, limit: limit));

  @override
  Future<Either<ApiFailure, UserDto>> createUser({
    required String username,
    required String password,
    String? displayName,
  }) {
    return _attempt(
      () => _api.users.create(
        CreateUserRequestDto(
          username: username,
          password: password,
          displayName: displayName,
        ),
      ),
    );
  }

  @override
  Future<Either<ApiFailure, UserDto>> updateUser({
    required int userId,
    required String? displayName,
    String? password,
  }) {
    return _attempt(
      () => _api.users.update(
        userId,
        UpdateUserRequestDto(displayName: displayName, password: password),
      ),
    );
  }

  @override
  Future<Either<ApiFailure, UserDto>> blockUser(int userId) =>
      _attempt(() => _api.users.block(userId));

  @override
  Future<Either<ApiFailure, UserDto>> unblockUser(int userId) =>
      _attempt(() => _api.users.unblock(userId));

  @override
  Future<Either<ApiFailure, Unit>> deleteUser(int userId) {
    return _attempt(() async {
      await _api.users.delete(userId);
      return unit;
    });
  }

  /// Every call in this repository has the same two outcomes, and the same
  /// one way of telling them apart (`ResourcesRepositoryImpl`).
  Future<Either<ApiFailure, T>> _attempt<T>(Future<T> Function() call) async {
    try {
      return right(await call());
    } on DioException catch (error) {
      return left(mapDioException(error));
    }
  }
}
