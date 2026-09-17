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
  }) = _GroupDetailState;

  const GroupDetailState._();

  bool get isEmpty => !loading && projects.isEmpty && failure == null;
}

/// One group's projects, and who has a role on it.
///
/// Teams are still not here — the server has no endpoints for them in this
/// stage (design.md «Delivery Phases»).
class GroupDetailCubit extends Cubit<GroupDetailState> {
  final ManageProjects _projects;
  final ManageRoleAssignments _roleAssignments;
  final int groupId;

  GroupDetailCubit({
    required ManageProjects projects,
    required ManageRoleAssignments roleAssignments,
    required this.groupId,
  }) : _projects = projects,
       _roleAssignments = roleAssignments,
       super(const GroupDetailState());

  Future<void> load() async {
    emit(state.copyWith(loading: true, failure: null));
    // Both, because the screen is not useful with either half missing — same
    // reasoning as `ProjectDetailCubit.load`. Unlike there, a failed access
    // lookup degrades to the previous list rather than surfacing [failure]:
    // the project list is the reason this screen exists, «Доступ» is a
    // section on it.
    final result = await _projects.inGroup(groupId);
    final access = await _roleAssignments.forScope(
      scopeType: 'group',
      scopeId: groupId,
    );
    if (isClosed) return;

    result.match(
      (failure) => emit(state.copyWith(loading: false, failure: failure)),
      (projects) => emit(
        state.copyWith(
          loading: false,
          projects: projects,
          roleAssignments: access.getOrElse((_) => state.roleAssignments),
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
}
