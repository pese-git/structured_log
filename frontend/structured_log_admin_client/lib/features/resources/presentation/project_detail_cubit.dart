import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../shared/api/cursor_page.dart';
import '../../../shared/api/api_failure.dart';
import '../../../shared/api/dto/resource_dto.dart';
import '../../../shared/api/dto/user_dto.dart';
import '../../role_assignments/application/manage_role_assignments.dart';
import '../application/manage_resources.dart';

part 'project_detail_cubit.freezed.dart';

@freezed
abstract class ProjectDetailState with _$ProjectDetailState {
  const factory ProjectDetailState({
    @Default(true) bool loading,
    ProjectDto? project,
    @Default(<SecretKeyDto>[]) List<SecretKeyDto> keys,
    @Default(false) bool saving,
    ApiFailure? failure,

    /// Refusals belonging to a dialog, kept off the page behind it.
    ApiFailure? actionFailure,

    /// The key just created, carrying the one and only copy of its value.
    ///
    /// Held for exactly as long as the reveal dialog is open and then dropped
    /// — it exists nowhere else, on the server included
    /// (`specs/admin-client-resource-management`).
    SecretKeyDto? revealedKey,

    /// Who has a role on this project — the «Доступ» section (уточнение
    /// 17.09.2026).
    @Default(<RoleAssignmentDto>[]) List<RoleAssignmentDto> roleAssignments,
    @Default(false) bool grantingAccess,
    ApiFailure? accessFailure,
  }) = _ProjectDetailState;

  const ProjectDetailState._();

  /// Loaded, and this project has never had a key.
  bool get hasNoKeys => !loading && keys.isEmpty;
}

class ProjectDetailCubit extends Cubit<ProjectDetailState> {
  final ManageProjects _projects;
  final ManageSecretKeys _keys;
  final ManageRoleAssignments _roleAssignments;
  final ManageTeams _teams;
  final int projectId;

  ProjectDetailCubit({
    required ManageProjects projects,
    required ManageSecretKeys keys,
    required ManageRoleAssignments roleAssignments,
    required ManageTeams teams,
    required this.projectId,
  }) : _projects = projects,
       _keys = keys,
       _roleAssignments = roleAssignments,
       _teams = teams,
       super(const ProjectDetailState());

  Future<void> load() async {
    emit(state.copyWith(loading: true, failure: null));
    // The quota comes from the project, the keys and the grant list each
    // from their own endpoint — the screen is not useful without the first
    // two; a failed access lookup degrades to the previous list instead,
    // same reasoning as `GroupDetailCubit.load`.
    final project = await _projects.get(projectId);
    final keys = await _keys.list(projectId);
    final access = await _roleAssignments.forScope(
      scopeType: 'project',
      scopeId: projectId,
    );
    if (isClosed) return;

    project.match(
      (failure) => emit(state.copyWith(loading: false, failure: failure)),
      (project) => emit(
        state.copyWith(
          loading: false,
          project: project,
          keys: keys.getOrElse((_) => const []),
          roleAssignments: access.getOrElse((_) => state.roleAssignments),
          failure: null,
        ),
      ),
    );
  }

  Future<void> grantAccess({
    required String subjectType,
    required int subjectId,
    required String role,
  }) async {
    if (state.grantingAccess) return;
    emit(state.copyWith(grantingAccess: true, accessFailure: null));
    final result = await _roleAssignments.grant(
      subjectType: subjectType,
      subjectId: subjectId,
      role: role,
      scopeType: 'project',
      scopeId: projectId,
    );
    if (isClosed) return;

    await result.match(
      (failure) async =>
          emit(state.copyWith(grantingAccess: false, accessFailure: failure)),
      (_) async {
        emit(state.copyWith(grantingAccess: false));
        await _reloadAccess();
      },
    );
  }

  Future<void> revokeAccess(int assignmentId) async {
    if (state.grantingAccess) return;
    emit(state.copyWith(grantingAccess: true, accessFailure: null));
    final result = await _roleAssignments.revoke(assignmentId);
    if (isClosed) return;

    await result.match(
      (failure) async =>
          emit(state.copyWith(grantingAccess: false, accessFailure: failure)),
      (_) async {
        emit(state.copyWith(grantingAccess: false));
        await _reloadAccess();
      },
    );
  }

  void clearAccessFailure() => emit(state.copyWith(accessFailure: null));

  Future<CursorPage<UserDto>> searchUsers(String query) =>
      _roleAssignments.searchUsers(query);

  /// This project's *enclosing group*'s teams — a team is never scoped to a
  /// project directly, and the server's own owner-delegation rule requires a
  /// team recipient to belong to the group a project sits in
  /// (`access_check.dart`'s `subjectTeamGroupId` check) — same reasoning and
  /// same client-side substring filter as `GroupDetailCubit.searchTeams`.
  /// Empty before [ProjectDetailState.project] has loaded, which is also the
  /// only time the «Предоставить доступ» dialog cannot yet be open.
  Future<List<TeamDto>> searchTeams(String query) async {
    final groupId = state.project?.groupId;
    if (groupId == null) return const [];
    final result = await _teams.inGroup(groupId);
    final teams = result.getOrElse((_) => const []);
    if (query.isEmpty) return teams;
    final needle = query.toLowerCase();
    return [
      for (final team in teams)
        if (team.name.toLowerCase().contains(needle)) team,
    ];
  }

  Future<void> _reloadAccess() async {
    final result = await _roleAssignments.forScope(
      scopeType: 'project',
      scopeId: projectId,
    );
    if (isClosed) return;
    result.match(
      (_) {},
      (items) => emit(state.copyWith(roleAssignments: items)),
    );
  }

  Future<void> updateQuota({
    required int retentionDays,
    required int? maxEntries,
    required int? maxBytes,
  }) async {
    if (state.saving) return;
    emit(state.copyWith(saving: true, actionFailure: null));
    final result = await _projects.updateQuota(
      projectId: projectId,
      retentionDays: retentionDays,
      maxEntries: maxEntries,
      maxBytes: maxBytes,
    );
    if (isClosed) return;

    result.match(
      (failure) => emit(state.copyWith(saving: false, actionFailure: failure)),
      // The answer carries the saved project, but not its usage counters —
      // those come only from `GET /v1/projects/{id}` — so the screen takes
      // the quota from here and keeps the counters it already had.
      (saved) => emit(
        state.copyWith(
          saving: false,
          project: saved.copyWith(
            entryCount: state.project?.entryCount,
            totalBytes: state.project?.totalBytes,
          ),
        ),
      ),
    );
  }

  Future<void> createKey(String label) async {
    if (state.saving) return;
    emit(state.copyWith(saving: true, actionFailure: null));
    final result = await _keys.create(projectId: projectId, label: label);
    if (isClosed) return;

    await result.match(
      (failure) async =>
          emit(state.copyWith(saving: false, actionFailure: failure)),
      (key) async {
        emit(state.copyWith(saving: false, revealedKey: key));
        await _reloadKeys();
      },
    );
  }

  /// Forgets the created key's value. Called when the reveal dialog closes,
  /// which is the moment the value stops existing anywhere.
  void dismissRevealedKey() => emit(state.copyWith(revealedKey: null));

  void clearActionFailure() => emit(state.copyWith(actionFailure: null));

  Future<void> revokeKey(int keyId) async {
    if (state.saving) return;
    emit(state.copyWith(saving: true, actionFailure: null));
    final result = await _keys.revoke(projectId: projectId, keyId: keyId);
    if (isClosed) return;

    await result.match(
      (failure) async =>
          emit(state.copyWith(saving: false, actionFailure: failure)),
      (_) async {
        emit(state.copyWith(saving: false));
        await _reloadKeys();
      },
    );
  }

  Future<void> setBlocked(bool blocked) async {
    if (state.saving) return;
    emit(state.copyWith(saving: true, actionFailure: null));
    final result = blocked
        ? await _projects.block(projectId)
        : await _projects.unblock(projectId);
    if (isClosed) return;

    result.match(
      (failure) => emit(state.copyWith(saving: false, actionFailure: failure)),
      // Same reasoning as `updateQuota`: the answer carries `is_blocked` but
      // not the usage counters, which only `GET /v1/projects/{id}` computes.
      (saved) => emit(
        state.copyWith(
          saving: false,
          project: saved.copyWith(
            entryCount: state.project?.entryCount,
            totalBytes: state.project?.totalBytes,
          ),
        ),
      ),
    );
  }

  Future<void> _reloadKeys() async {
    final keys = await _keys.list(projectId);
    if (isClosed) return;
    keys.match((_) {}, (keys) => emit(state.copyWith(keys: keys)));
  }
}
