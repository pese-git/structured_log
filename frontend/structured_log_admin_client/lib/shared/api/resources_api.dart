import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import 'dto/resource_dto.dart';

part 'resources_api.g.dart';

/// `/v1/groups` and the projects under them.
@RestApi()
abstract class GroupsApi {
  factory GroupsApi(Dio dio, {String baseUrl}) = _GroupsApi;

  /// Returns only the groups the caller can see; an administrator sees all.
  ///
  /// Wrapped in [GroupListDto], not a bare list — the server envelopes every
  /// collection as `{"items": [...]}`, and declaring the bare form here made
  /// dio throw on the cast and the screen say the server was unreachable.
  @GET('/v1/groups')
  Future<GroupListDto> list();

  /// Administrators only — the server answers 403 to anyone else.
  @POST('/v1/groups')
  Future<GroupDto> create(@Body() CreateGroupRequestDto body);

  @POST('/v1/groups/{groupId}/projects')
  Future<ProjectDto> createProject(
    @Path('groupId') int groupId,
    @Body() CreateProjectRequestDto body,
  );
}

/// `/v1/projects/*`.
@RestApi()
abstract class ProjectsApi {
  factory ProjectsApi(Dio dio, {String baseUrl}) = _ProjectsApi;

  /// Every project the caller may read, flat: a role granted on one project
  /// does not cover its group, so such a user sees no groups at all and this
  /// is their only way to find it.
  ///
  /// Carries no usage counters — those come from [get], one project at a
  /// time.
  @GET('/v1/projects')
  Future<ProjectListDto> list({@Query('group_id') int? groupId});

  /// The only endpoint that reports usage: `entry_count` and `total_bytes`
  /// come back here and nowhere else.
  @GET('/v1/projects/{id}')
  Future<ProjectDto> get(@Path('id') int id);

  /// Replaces the quota. `owner` of the project's group, or `admin`; the
  /// server refuses anyone else.
  @PATCH('/v1/projects/{id}')
  Future<ProjectDto> updateQuota(
    @Path('id') int id,
    @Body() UpdateProjectQuotaRequestDto body,
  );

  /// `admin` only — not even `owner` of the project's own group
  /// (`docs/architecture/rbac-and-lifecycle.md`). Halts ingestion and direct
  /// reads of this project; does not revoke its secret keys.
  @POST('/v1/projects/{id}/block')
  Future<ProjectDto> block(@Path('id') int id);

  @POST('/v1/projects/{id}/unblock')
  Future<ProjectDto> unblock(@Path('id') int id);
}

/// `/v1/projects/{id}/secret-keys`.
@RestApi()
abstract class SecretKeysApi {
  factory SecretKeysApi(Dio dio, {String baseUrl}) = _SecretKeysApi;

  /// Metadata only — no response here ever carries a key's value.
  @GET('/v1/projects/{id}/secret-keys')
  Future<SecretKeyListDto> list(@Path('id') int projectId);

  /// The one response that contains `secret`. It is not retrievable
  /// afterwards, so whatever calls this must show the value before it is
  /// discarded.
  @POST('/v1/projects/{id}/secret-keys')
  Future<SecretKeyDto> create(
    @Path('id') int projectId,
    @Body() CreateSecretKeyRequestDto body,
  );

  @DELETE('/v1/projects/{id}/secret-keys/{keyId}')
  Future<void> revoke(@Path('id') int projectId, @Path('keyId') int keyId);
}
