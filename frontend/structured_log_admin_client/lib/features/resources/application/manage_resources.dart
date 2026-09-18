import 'package:fpdart/fpdart.dart';

import '../../../shared/api/api_failure.dart';
import '../../../shared/api/dto/resource_dto.dart';
import '../domain/resources_repository.dart';

/// Three use cases, not eleven.
///
/// Each of these is one screen's worth of work — the group list, a group's
/// projects, a project's keys — and the calls inside one are always made by
/// the same screen, about the same thing. Splitting them one method per class
/// would give eleven single-line files whose names repeat their method, and a
/// reader asking "what can the project screen do" would have to open five of
/// them.
class ManageGroups {
  final ResourcesRepository _repository;

  const ManageGroups(this._repository);

  Future<Either<ApiFailure, List<GroupDto>>> list() => _repository.groups();

  Future<Either<ApiFailure, GroupDto>> create(String name) =>
      _repository.createGroup(name);
}

class ManageProjects {
  final ResourcesRepository _repository;

  const ManageProjects(this._repository);

  Future<Either<ApiFailure, List<ProjectDto>>> inGroup(int groupId) =>
      _repository.projectsOf(groupId);

  /// With usage counters, which the list does not carry.
  Future<Either<ApiFailure, ProjectDto>> get(int projectId) =>
      _repository.project(projectId);

  Future<Either<ApiFailure, ProjectDto>> create({
    required int groupId,
    required String name,
    required int retentionDays,
    int? maxEntries,
    int? maxBytes,
  }) {
    return _repository.createProject(
      groupId: groupId,
      name: name,
      retentionDays: retentionDays,
      maxEntries: maxEntries,
      maxBytes: maxBytes,
    );
  }

  Future<Either<ApiFailure, ProjectDto>> updateQuota({
    required int projectId,
    required int retentionDays,
    required int? maxEntries,
    required int? maxBytes,
  }) {
    return _repository.updateQuota(
      projectId: projectId,
      retentionDays: retentionDays,
      maxEntries: maxEntries,
      maxBytes: maxBytes,
    );
  }

  Future<Either<ApiFailure, ProjectDto>> block(int projectId) =>
      _repository.blockProject(projectId);

  Future<Either<ApiFailure, ProjectDto>> unblock(int projectId) =>
      _repository.unblockProject(projectId);
}

class ManageTeams {
  final ResourcesRepository _repository;

  const ManageTeams(this._repository);

  Future<Either<ApiFailure, List<TeamDto>>> inGroup(int groupId) =>
      _repository.teamsOf(groupId);

  Future<Either<ApiFailure, TeamDto>> create({
    required int groupId,
    required String name,
  }) => _repository.createTeam(groupId: groupId, name: name);

  Future<Either<ApiFailure, List<TeamMemberDto>>> members(int teamId) =>
      _repository.teamMembers(teamId);

  Future<Either<ApiFailure, Unit>> addMember({
    required int teamId,
    required int userId,
  }) => _repository.addTeamMember(teamId: teamId, userId: userId);

  Future<Either<ApiFailure, Unit>> removeMember({
    required int teamId,
    required int userId,
  }) => _repository.removeTeamMember(teamId: teamId, userId: userId);
}

class ManageSecretKeys {
  final ResourcesRepository _repository;

  const ManageSecretKeys(this._repository);

  Future<Either<ApiFailure, List<SecretKeyDto>>> list(int projectId) =>
      _repository.secretKeys(projectId);

  /// The returned key carries `secret` exactly once. Whatever calls this has
  /// to show it before letting it go.
  Future<Either<ApiFailure, SecretKeyDto>> create({
    required int projectId,
    required String label,
  }) {
    return _repository.createSecretKey(projectId: projectId, label: label);
  }

  Future<Either<ApiFailure, Unit>> revoke({
    required int projectId,
    required int keyId,
  }) {
    return _repository.revokeSecretKey(projectId: projectId, keyId: keyId);
  }
}
