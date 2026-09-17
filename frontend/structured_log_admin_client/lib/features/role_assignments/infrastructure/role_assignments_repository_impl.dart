import 'package:dio/dio.dart';
import 'package:fpdart/fpdart.dart';

import '../../../shared/api/api_client.dart';
import '../../../shared/api/api_failure.dart';
import '../../../shared/api/dto/user_dto.dart';
import '../../../shared/api/failure_mapper.dart';
import '../domain/role_assignments_repository.dart';

class RoleAssignmentsRepositoryImpl implements RoleAssignmentsRepository {
  final ApiClient _api;

  const RoleAssignmentsRepositoryImpl(this._api);

  @override
  Future<Either<ApiFailure, List<RoleAssignmentDto>>> forUser(int userId) {
    return _attempt(() async {
      final page = await _api.roleAssignments.list(subjectId: userId);
      return page.items;
    });
  }

  @override
  Future<Either<ApiFailure, List<RoleAssignmentDto>>> forScope({
    required String scopeType,
    required int scopeId,
  }) {
    return _attempt(() async {
      final page = await _api.roleAssignments.list(
        scopeType: scopeType,
        scopeId: scopeId,
      );
      return page.items;
    });
  }

  @override
  Future<Either<ApiFailure, RoleAssignmentDto>> grant({
    required int subjectId,
    required String role,
    required String scopeType,
    int? scopeId,
  }) {
    return _attempt(
      () => _api.roleAssignments.create(
        CreateRoleAssignmentRequestDto(
          subjectType: 'user',
          subjectId: subjectId,
          role: role,
          scopeType: scopeType,
          scopeId: scopeId,
        ),
      ),
    );
  }

  @override
  Future<Either<ApiFailure, Unit>> revoke(int assignmentId) {
    return _attempt(() async {
      await _api.roleAssignments.delete(assignmentId);
      return unit;
    });
  }

  @override
  Future<Either<ApiFailure, List<UserDto>>> searchUsers(String username) {
    return _attempt(() async {
      final page = await _api.users.list(username: username, limit: 20);
      return page.items;
    });
  }

  /// Same two outcomes, same one way of telling them apart, as every other
  /// repository in this client (`UsersRepositoryImpl`, `ResourcesRepositoryImpl`).
  Future<Either<ApiFailure, T>> _attempt<T>(Future<T> Function() call) async {
    try {
      return right(await call());
    } on DioException catch (error) {
      return left(mapDioException(error));
    }
  }
}
