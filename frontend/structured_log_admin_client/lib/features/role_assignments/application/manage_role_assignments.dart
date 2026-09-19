import 'package:fpdart/fpdart.dart';

import '../../../shared/api/api_failure.dart';
import '../../../shared/api/cursor_page.dart';
import '../../../shared/api/dto/user_dto.dart';
import '../domain/role_assignments_repository.dart';

/// Used from both the users screen and the resources screens — unlike
/// `ManageUsers`/`ManageGroups`, this is not one class per screen, because
/// the underlying grants are not either (design.md, уточнение 17.09.2026).
class ManageRoleAssignments {
  final RoleAssignmentsRepository _repository;

  const ManageRoleAssignments(this._repository);

  Future<Either<ApiFailure, List<RoleAssignmentDto>>> forUser(int userId) =>
      _repository.forUser(userId);

  Future<Either<ApiFailure, List<RoleAssignmentDto>>> forScope({
    required String scopeType,
    required int scopeId,
  }) => _repository.forScope(scopeType: scopeType, scopeId: scopeId);

  Future<Either<ApiFailure, RoleAssignmentDto>> grant({
    required String subjectType,
    required int subjectId,
    required String role,
    required String scopeType,
    int? scopeId,
  }) {
    return _repository.grant(
      subjectType: subjectType,
      subjectId: subjectId,
      role: role,
      scopeType: scopeType,
      scopeId: scopeId,
    );
  }

  Future<Either<ApiFailure, Unit>> revoke(int assignmentId) =>
      _repository.revoke(assignmentId);

  /// Degrades to an empty result on failure, same reasoning as
  /// `UsersCubit.searchGroups`/`searchProjects`: a search box coming up empty
  /// reads as "no matches yet", not as a form-level error.
  ///
  /// One page: the picker shows it, and says so when there was more
  /// ([CursorPage.hasMore]) instead of letting the cut read as the end.
  Future<CursorPage<UserDto>> searchUsers(String query) async {
    final result = await _repository.searchUsers(query);
    return result.getOrElse((_) => const CursorPage(<UserDto>[], null));
  }
}
