import 'package:fpdart/fpdart.dart';

import '../../../shared/api/api_failure.dart';
import '../../../shared/api/dto/user_dto.dart';

/// User accounts (`design.md` "Delivery Phases", Этап 3: create/block/
/// delete). Role assignments live in `RoleAssignmentsRepository` next door,
/// not here — a user's grants are read/written from both this feature's Edit
/// dialog and the resources feature's group/project «Доступ» section, so
/// neither owns them exclusively (уточнение 17.09.2026).
///
/// The DTOs travel as-is, as in `ResourcesRepository` next door — no email
/// field on this client.
abstract interface class UsersRepository {
  /// The first page, newest account first.
  Future<Either<ApiFailure, UserPageDto>> firstPage({int? limit});

  /// The next, older page — `cursor` from a previous [firstPage]/[nextPage].
  Future<Either<ApiFailure, UserPageDto>> nextPage({
    required String cursor,
    int? limit,
  });

  /// `must_change_password: true` on the created account, always — a
  /// password an admin chose is never the account's own choice.
  Future<Either<ApiFailure, UserDto>> createUser({
    required String username,
    required String password,
    String? displayName,
  });

  /// [displayName] is sent as given, including `null` to clear it — see
  /// `UpdateUserRequestDto`. A non-null [password] marks the account's
  /// password temporary and ends its current sessions.
  Future<Either<ApiFailure, UserDto>> updateUser({
    required int userId,
    required String? displayName,
    String? password,
  });

  /// `admin` only, not even the target's own group `owner`. Ends the
  /// target's current sessions.
  Future<Either<ApiFailure, UserDto>> blockUser(int userId);

  /// Refused with `409 deleted_account` (`ConflictFailure`) if the target
  /// was deleted rather than blocked.
  Future<Either<ApiFailure, UserDto>> unblockUser(int userId);

  /// `admin` only, no password required from the target. Refused with
  /// `403 cannot_delete_primary_admin` or `409 sole_group_owner` — the
  /// latter carries `blocking_groups` in `ConflictFailure.details`.
  Future<Either<ApiFailure, Unit>> deleteUser(int userId);
}
