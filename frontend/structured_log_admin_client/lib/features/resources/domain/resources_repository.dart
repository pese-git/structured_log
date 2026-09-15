import 'package:fpdart/fpdart.dart';

import '../../../shared/api/api_failure.dart';
import '../../../shared/api/dto/resource_dto.dart';

/// Groups, the projects inside them, and the keys that let an application
/// send logs to a project.
///
/// The DTOs travel as they are, as in the log browser: they are already plain
/// values that mirror the wire, and a second identical set of domain classes
/// would be ceremony rather than insulation.
///
/// Users, teams and role assignments are deliberately absent — the server has
/// no endpoints for them in this stage (design.md «Delivery Phases»).
abstract interface class ResourcesRepository {
  /// Groups the caller can see. An administrator sees all of them.
  Future<Either<ApiFailure, List<GroupDto>>> groups();

  /// Administrators only; anyone else is refused by the server.
  Future<Either<ApiFailure, GroupDto>> createGroup(String name);

  /// Projects inside one group.
  ///
  /// Carries no usage counters — those come from [project], one at a time,
  /// which is the only endpoint that computes them.
  Future<Either<ApiFailure, List<ProjectDto>>> projectsOf(int groupId);

  /// One project, with `entry_count`/`total_bytes` filled in.
  Future<Either<ApiFailure, ProjectDto>> project(int projectId);

  Future<Either<ApiFailure, ProjectDto>> createProject({
    required int groupId,
    required String name,
    required int retentionDays,
    int? maxEntries,
    int? maxBytes,
  });

  /// Replaces the quota. A `null` limit means unlimited, and is sent as such:
  /// the server tells "leave this alone" from "make this unlimited" by
  /// whether the key is present at all, so both are expressed here.
  Future<Either<ApiFailure, ProjectDto>> updateQuota({
    required int projectId,
    required int retentionDays,
    required int? maxEntries,
    required int? maxBytes,
  });

  /// Key metadata. No response here ever carries a key's value.
  Future<Either<ApiFailure, List<SecretKeyDto>>> secretKeys(int projectId);

  /// The one call that answers with `secret`. It cannot be retrieved
  /// afterwards, so whatever calls this must show the value before dropping
  /// it (`specs/admin-client-resource-management`).
  Future<Either<ApiFailure, SecretKeyDto>> createSecretKey({
    required int projectId,
    required String label,
  });

  Future<Either<ApiFailure, Unit>> revokeSecretKey({
    required int projectId,
    required int keyId,
  });
}
