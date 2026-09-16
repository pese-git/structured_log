import 'package:fpdart/fpdart.dart';

import '../../../shared/api/api_failure.dart';
import '../../../shared/api/dto/user_dto.dart';
import '../domain/users_repository.dart';

/// One screen's worth of work — the users list, its create/edit dialogs, and
/// the reduced role-grant form (`ManageGroups`/`ManageProjects` next door
/// follow the same one-class-per-screen rule).
class ManageUsers {
  final UsersRepository _repository;

  const ManageUsers(this._repository);

  Future<Either<ApiFailure, UserPageDto>> firstPage({int? limit}) =>
      _repository.firstPage(limit: limit);

  Future<Either<ApiFailure, UserPageDto>> nextPage({
    required String cursor,
    int? limit,
  }) => _repository.nextPage(cursor: cursor, limit: limit);

  Future<Either<ApiFailure, UserDto>> create({
    required String username,
    required String password,
    String? displayName,
  }) {
    return _repository.createUser(
      username: username,
      password: password,
      displayName: displayName,
    );
  }

  Future<Either<ApiFailure, UserDto>> update({
    required int userId,
    required String? displayName,
    String? password,
  }) {
    return _repository.updateUser(
      userId: userId,
      displayName: displayName,
      password: password,
    );
  }

  Future<Either<ApiFailure, UserDto>> block(int userId) =>
      _repository.blockUser(userId);

  Future<Either<ApiFailure, UserDto>> unblock(int userId) =>
      _repository.unblockUser(userId);

  Future<Either<ApiFailure, Unit>> delete(int userId) =>
      _repository.deleteUser(userId);

  Future<Either<ApiFailure, RoleAssignmentDto>> grantRole({
    required int userId,
    required String role,
    required String scopeType,
    int? scopeId,
  }) {
    return _repository.grantRole(
      userId: userId,
      role: role,
      scopeType: scopeType,
      scopeId: scopeId,
    );
  }
}
