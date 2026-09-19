import 'package:fpdart/fpdart.dart';

import '../../../shared/api/api_failure.dart';
import '../../../shared/api/cursor_page.dart';
import '../../../shared/api/dto/user_dto.dart';

/// `RoleAssignment`s — the grants a user holds, from either side of them.
///
/// Own feature, not folded into `UsersRepository`/`ResourcesRepository`: it
/// is used from both — the Edit User dialog (`forUser`, one subject, any
/// scope) and a group/project's «Доступ» section (`forScope`, one scope, any
/// subject) — the same asymmetry the server's `GET /v1/role-assignments`
/// filter shape reflects (design.md, уточнение 17.09.2026). Bound in both
/// the `users` and `resources` subscopes (`users_module.dart`/
/// `resources_module.dart`), same reasoning as `ResourcesRepository` being
/// rebound into `users_module.dart` already.
abstract interface class RoleAssignmentsRepository {
  /// Every grant held by [userId], any scope.
  Future<Either<ApiFailure, List<RoleAssignmentDto>>> forUser(int userId);

  /// Every grant held on one group/project — [scopeType] is `"group"` or
  /// `"project"`, never `"global"` (nothing is "on" the global scope).
  Future<Either<ApiFailure, List<RoleAssignmentDto>>> forScope({
    required String scopeType,
    required int scopeId,
  });

  /// [subjectType] is `"user"` or `"team"` (13.5, full version — the server
  /// has accepted `"team"` since 5.6). [scopeId] is required unless
  /// [scopeType] is `"global"`.
  Future<Either<ApiFailure, RoleAssignmentDto>> grant({
    required String subjectType,
    required int subjectId,
    required String role,
    required String scopeType,
    int? scopeId,
  });

  Future<Either<ApiFailure, Unit>> revoke(int assignmentId);

  /// Candidate subjects for a group/project's «Предоставить доступ» dialog —
  /// [username] narrows by substring, same idiom as `AdminSearchPicker`'s use
  /// of `ResourcesRepository.groups`/`searchProjects`.
  Future<Either<ApiFailure, CursorPage<UserDto>>> searchUsers(String username);
}
