import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../shared/api/api_failure.dart';
import '../../../shared/api/dto/resource_dto.dart';
import '../../../shared/api/dto/user_dto.dart';
import '../../role_assignments/application/manage_role_assignments.dart';
import '../application/manage_resources.dart';

part 'group_detail_cubit.freezed.dart';

@freezed
abstract class GroupDetailState with _$GroupDetailState {
  const factory GroupDetailState({
    @Default(true) bool loading,
    @Default(<ProjectDto>[]) List<ProjectDto> projects,
    @Default(false) bool creating,
    ApiFailure? failure,
    ApiFailure? createFailure,
    @Default(false) bool created,

    /// Who has a role on this group — the «Доступ» section (уточнение
    /// 17.09.2026).
    @Default(<RoleAssignmentDto>[]) List<RoleAssignmentDto> roleAssignments,
    @Default(false) bool grantingAccess,
    ApiFailure? accessFailure,

    /// This group's teams — the «Команды» section (13.2a).
    @Default(<TeamDto>[]) List<TeamDto> teams,
    @Default(false) bool creatingTeam,
    ApiFailure? createTeamFailure,
    @Default(false) bool teamCreated,

    /// The composition dialog, for at most one team at a time — `null` when
    /// none is open.
    int? managingTeamId,
    @Default(<TeamMemberDto>[]) List<TeamMemberDto> teamMembers,
    @Default(false) bool loadingTeamMembers,
    @Default(false) bool changingTeamMembers,
    ApiFailure? teamMembersFailure,
  }) = _GroupDetailState;

  const GroupDetailState._();

  bool get isEmpty => !loading && projects.isEmpty && failure == null;
}

/// One group's projects, its teams, and who has a role on it.
class GroupDetailCubit extends Cubit<GroupDetailState> {
  final ManageProjects _projects;
  final ManageRoleAssignments _roleAssignments;
  final ManageTeams _teams;
  final int groupId;

  GroupDetailCubit({
    required ManageProjects projects,
    required ManageRoleAssignments roleAssignments,
    required ManageTeams teams,
    required this.groupId,
  }) : _projects = projects,
       _roleAssignments = roleAssignments,
       _teams = teams,
       super(const GroupDetailState());

  Future<void> load() async {
    emit(state.copyWith(loading: true, failure: null));
    // All three, because the screen is not useful with the projects half
    // missing — same reasoning as `ProjectDetailCubit.load`. Teams and access
    // degrade to the previous list rather than surfacing [failure]: the
    // project list is the reason this screen exists, «Команды»/«Доступ» are
    // sections on it.
    final result = await _projects.inGroup(groupId);
    final access = await _roleAssignments.forScope(
      scopeType: 'group',
      scopeId: groupId,
    );
    final teams = await _teams.inGroup(groupId);
    if (isClosed) return;

    result.match(
      (failure) => emit(state.copyWith(loading: false, failure: failure)),
      (projects) => emit(
        state.copyWith(
          loading: false,
          projects: projects,
          roleAssignments: access.getOrElse((_) => state.roleAssignments),
          teams: teams.getOrElse((_) => state.teams),
          failure: null,
        ),
      ),
    );
  }

  Future<void> grantAccess({required int userId, required String role}) async {
    if (state.grantingAccess) return;
    emit(state.copyWith(grantingAccess: true, accessFailure: null));
    final result = await _roleAssignments.grant(
      subjectId: userId,
      role: role,
      scopeType: 'group',
      scopeId: groupId,
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

  Future<List<UserDto>> searchUsers(String query) =>
      _roleAssignments.searchUsers(query);

  Future<void> _reloadAccess() async {
    final result = await _roleAssignments.forScope(
      scopeType: 'group',
      scopeId: groupId,
    );
    if (isClosed) return;
    result.match(
      (_) {},
      (items) => emit(state.copyWith(roleAssignments: items)),
    );
  }

  Future<void> create({
    required String name,
    required int retentionDays,
    int? maxEntries,
    int? maxBytes,
  }) async {
    if (state.creating) return;
    emit(state.copyWith(creating: true, createFailure: null, created: false));
    final result = await _projects.create(
      groupId: groupId,
      name: name,
      retentionDays: retentionDays,
      maxEntries: maxEntries,
      maxBytes: maxBytes,
    );
    if (isClosed) return;

    await result.match(
      (failure) async =>
          emit(state.copyWith(creating: false, createFailure: failure)),
      (_) async {
        emit(state.copyWith(creating: false, created: true));
        await load();
      },
    );
  }

  void dialogClosed() =>
      emit(state.copyWith(created: false, createFailure: null));

  Future<void> createTeam(String name) async {
    if (state.creatingTeam) return;
    emit(
      state.copyWith(
        creatingTeam: true,
        createTeamFailure: null,
        teamCreated: false,
      ),
    );
    final result = await _teams.create(groupId: groupId, name: name);
    if (isClosed) return;

    await result.match(
      (failure) async =>
          emit(state.copyWith(creatingTeam: false, createTeamFailure: failure)),
      (_) async {
        emit(state.copyWith(creatingTeam: false, teamCreated: true));
        final reloaded = await _teams.inGroup(groupId);
        if (isClosed) return;
        reloaded.match((_) {}, (items) => emit(state.copyWith(teams: items)));
      },
    );
  }

  void teamDialogClosed() =>
      emit(state.copyWith(teamCreated: false, createTeamFailure: null));

  /// Opens the composition dialog for [teamId] and loads its current
  /// members.
  Future<void> openTeamMembers(int teamId) async {
    emit(
      state.copyWith(
        managingTeamId: teamId,
        teamMembers: const [],
        loadingTeamMembers: true,
        teamMembersFailure: null,
      ),
    );
    await _reloadTeamMembers(teamId);
  }

  void closeTeamMembers() =>
      emit(state.copyWith(managingTeamId: null, teamMembers: const []));

  Future<void> addTeamMember(int userId) async {
    final teamId = state.managingTeamId;
    if (teamId == null || state.changingTeamMembers) return;
    emit(state.copyWith(changingTeamMembers: true, teamMembersFailure: null));
    final result = await _teams.addMember(teamId: teamId, userId: userId);
    if (isClosed) return;

    await result.match(
      (failure) async => emit(
        state.copyWith(changingTeamMembers: false, teamMembersFailure: failure),
      ),
      (_) async {
        emit(state.copyWith(changingTeamMembers: false));
        await _reloadTeamMembers(teamId);
      },
    );
  }

  Future<void> removeTeamMember(int userId) async {
    final teamId = state.managingTeamId;
    if (teamId == null || state.changingTeamMembers) return;
    emit(state.copyWith(changingTeamMembers: true, teamMembersFailure: null));
    final result = await _teams.removeMember(teamId: teamId, userId: userId);
    if (isClosed) return;

    await result.match(
      (failure) async => emit(
        state.copyWith(changingTeamMembers: false, teamMembersFailure: failure),
      ),
      (_) async {
        emit(state.copyWith(changingTeamMembers: false));
        await _reloadTeamMembers(teamId);
      },
    );
  }

  Future<void> _reloadTeamMembers(int teamId) async {
    final result = await _teams.members(teamId);
    if (isClosed) return;
    result.match(
      (failure) => emit(
        state.copyWith(loadingTeamMembers: false, teamMembersFailure: failure),
      ),
      (members) =>
          emit(state.copyWith(loadingTeamMembers: false, teamMembers: members)),
    );
  }
}
