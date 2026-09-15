import 'package:dio/dio.dart';
import 'package:fpdart/fpdart.dart';

import '../../../shared/api/api_client.dart';
import '../../../shared/api/api_failure.dart';
import '../../../shared/api/dto/resource_dto.dart';
import '../../../shared/api/failure_mapper.dart';
import '../domain/resources_repository.dart';

class ResourcesRepositoryImpl implements ResourcesRepository {
  final ApiClient _api;

  const ResourcesRepositoryImpl(this._api);

  @override
  Future<Either<ApiFailure, List<GroupDto>>> groups() =>
      _attempt(() async => (await _api.groups.list()).items);

  @override
  Future<Either<ApiFailure, GroupDto>> createGroup(String name) =>
      _attempt(() => _api.groups.create(CreateGroupRequestDto(name: name)));

  @override
  Future<Either<ApiFailure, List<ProjectDto>>> projectsOf(int groupId) =>
      _attempt(() async => (await _api.projects.list(groupId: groupId)).items);

  @override
  Future<Either<ApiFailure, ProjectDto>> project(int projectId) =>
      _attempt(() => _api.projects.get(projectId));

  @override
  Future<Either<ApiFailure, ProjectDto>> createProject({
    required int groupId,
    required String name,
    required int retentionDays,
    int? maxEntries,
    int? maxBytes,
  }) {
    return _attempt(
      () => _api.groups.createProject(
        groupId,
        CreateProjectRequestDto(
          name: name,
          retentionDays: retentionDays,
          maxEntries: maxEntries,
          maxBytes: maxBytes,
        ),
      ),
    );
  }

  @override
  Future<Either<ApiFailure, ProjectDto>> updateQuota({
    required int projectId,
    required int retentionDays,
    required int? maxEntries,
    required int? maxBytes,
  }) {
    return _attempt(
      () => _api.projects.updateQuota(
        projectId,
        UpdateProjectQuotaRequestDto(
          retentionDays: retentionDays,
          maxEntries: maxEntries,
          maxBytes: maxBytes,
        ),
      ),
    );
  }

  @override
  Future<Either<ApiFailure, List<SecretKeyDto>>> secretKeys(int projectId) =>
      _attempt(() async => (await _api.secretKeys.list(projectId)).items);

  @override
  Future<Either<ApiFailure, SecretKeyDto>> createSecretKey({
    required int projectId,
    required String label,
  }) {
    return _attempt(
      () => _api.secretKeys.create(
        projectId,
        CreateSecretKeyRequestDto(label: label),
      ),
    );
  }

  @override
  Future<Either<ApiFailure, Unit>> revokeSecretKey({
    required int projectId,
    required int keyId,
  }) {
    return _attempt(() async {
      await _api.secretKeys.revoke(projectId, keyId);
      return unit;
    });
  }

  /// Every call in this repository has the same two outcomes, and the same
  /// one way of telling them apart.
  Future<Either<ApiFailure, T>> _attempt<T>(Future<T> Function() call) async {
    try {
      return right(await call());
    } on DioException catch (error) {
      return left(mapDioException(error));
    }
  }
}
