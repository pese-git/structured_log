import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fpdart/fpdart.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../shared/api/api_failure.dart';
import '../../../shared/api/dto/audit_dto.dart';
import '../../../shared/api/dto/resource_dto.dart';
import '../../../shared/api/dto/user_dto.dart';
import '../../audit/application/query_audit_log.dart';
import '../../audit/domain/audit_filter.dart';
import '../../resources/domain/resources_repository.dart';
import '../../role_assignments/application/manage_role_assignments.dart';
import '../application/manage_users.dart';

part 'users_cubit.freezed.dart';

@freezed
abstract class UsersState with _$UsersState {
  const factory UsersState({
    @Default(true) bool loading,

    /// The next, older page is on its way. Separate from [loading] so the
    /// rows already on screen stay put while it arrives (`AuditState`, same
    /// reasoning).
    @Default(false) bool loadingMore,
    @Default(<UserDto>[]) List<UserDto> users,

    /// For the next, older page; `null` once the server says there is
    /// nothing older.
    String? cursor,
    ApiFailure? failure,

    /// A create is in flight. Separate from [loading] so the list stays on
    /// screen while the dialog works.
    @Default(false) bool creating,
    ApiFailure? createFailure,

    /// Set once a create succeeds, so the dialog can close itself.
    @Default(false) bool created,

    /// Covers edit, block/unblock, delete and the role grant/revoke — all
    /// reach the server from the same open edit dialog, never two at once.
    @Default(false) bool saving,
    ApiFailure? actionFailure,

    /// The open edit dialog's subject's current grants — loaded when the
    /// dialog opens, refreshed after a grant or a revoke.
    @Default(<RoleAssignmentDto>[]) List<RoleAssignmentDto> roleAssignments,

    /// `UserDetailPage`'s "Последние события аудита" card — this user's most
    /// recent audit entries as actor, loaded when the page opens. Not tied to
    /// [saving]/[actionFailure]: a failed audit read should not block the
    /// rest of the page the way a failed grant does.
    @Default(<AuditEntryDto>[]) List<AuditEntryDto> recentAudit,
    @Default(false) bool loadingRecentAudit,
  }) = _UsersState;

  const UsersState._();

  bool get hasMore => cursor != null;

  /// Loaded, and there is nothing in it.
  bool get isEmpty => !loading && users.isEmpty && failure == null;
}

/// The users screen's state: one page at a time, and the four actions a row
/// or its edit dialog can take.
class UsersCubit extends Cubit<UsersState> {
  final ManageUsers _users;
  final ResourcesRepository _resources;
  final ManageRoleAssignments _roleAssignments;
  final QueryAuditLog _auditLog;

  /// The server's own default (`users_route.dart`); passed explicitly so a
  /// reader of this file does not have to know that to follow [loadMore].
  static const _pageSize = 50;

  /// How many rows `UserDetailPage`'s audit card draws.
  static const _recentAuditCount = 3;

  UsersCubit(
    this._users,
    this._resources,
    this._roleAssignments,
    this._auditLog,
  ) : super(const UsersState());

  Future<void> load() async {
    emit(state.copyWith(loading: true, failure: null));
    final result = await _users.firstPage(limit: _pageSize);
    if (isClosed) return;

    result.match(
      (failure) => emit(state.copyWith(loading: false, failure: failure)),
      (page) => emit(
        state.copyWith(
          loading: false,
          users: page.items,
          cursor: page.nextCursor,
          failure: null,
        ),
      ),
    );
  }

  Future<void> loadMore() async {
    final cursor = state.cursor;
    if (cursor == null || state.loadingMore || state.loading) return;

    emit(state.copyWith(loadingMore: true));
    final result = await _users.nextPage(cursor: cursor, limit: _pageSize);
    if (isClosed) return;

    result.match(
      (failure) => emit(state.copyWith(loadingMore: false, failure: failure)),
      (page) => emit(
        state.copyWith(
          loadingMore: false,
          users: [...state.users, ...page.items],
          cursor: page.nextCursor,
        ),
      ),
    );
  }

  Future<void> create({
    required String username,
    required String password,
    String? displayName,
  }) async {
    if (state.creating) return;
    emit(state.copyWith(creating: true, createFailure: null, created: false));
    final result = await _users.create(
      username: username,
      password: password,
      displayName: displayName,
    );
    if (isClosed) return;

    result.match(
      (failure) =>
          emit(state.copyWith(creating: false, createFailure: failure)),
      // Prepended, not reloaded: `GET /v1/users` orders newest-id-first, so
      // the new account belongs exactly here — and a full reload would reset
      // the reader to page one, losing however far into the list they had
      // scrolled.
      (created) => emit(
        state.copyWith(
          creating: false,
          created: true,
          users: [created, ...state.users],
        ),
      ),
    );
  }

  /// Clears the create dialog's one-shot flags, after it has acted on them.
  void dialogClosed() =>
      emit(state.copyWith(created: false, createFailure: null));

  /// Clears the open detail/edit page's flags, after it has acted on them —
  /// including the grant list and the audit card, so the next one opened does
  /// not flash the previous subject's data before [loadRoleAssignments]/
  /// [loadRecentAudit] replace them.
  void clearActionFailure() => emit(
    state.copyWith(
      actionFailure: null,
      roleAssignments: const [],
      recentAudit: const [],
    ),
  );

  /// The open detail page's subject's current grants.
  Future<void> loadRoleAssignments(int userId) async {
    final result = await _roleAssignments.forUser(userId);
    if (isClosed) return;
    result.match(
      (failure) => emit(state.copyWith(actionFailure: failure)),
      (items) => emit(state.copyWith(roleAssignments: items)),
    );
  }

  /// `UserDetailPage`'s "Последние события аудита" card. Degrades to an
  /// empty list on failure rather than surfacing [state.actionFailure]: one
  /// card failing to load is not reason enough to block the rest of the page
  /// (`searchGroups`/`searchProjects` below use the same reasoning).
  Future<void> loadRecentAudit(int userId) async {
    emit(state.copyWith(loadingRecentAudit: true));
    final result = await _auditLog.first(
      filter: AuditFilter(actorUserId: userId),
      limit: _recentAuditCount,
    );
    if (isClosed) return;
    emit(
      state.copyWith(
        loadingRecentAudit: false,
        recentAudit: result.match((_) => state.recentAudit, (p) => p.items),
      ),
    );
  }

  Future<void> update({
    required int userId,
    required String? displayName,
    String? password,
  }) async {
    if (state.saving) return;
    emit(state.copyWith(saving: true, actionFailure: null));
    final result = await _users.update(
      userId: userId,
      displayName: displayName,
      password: password,
    );
    if (isClosed) return;

    result.match(
      (failure) => emit(state.copyWith(saving: false, actionFailure: failure)),
      (updated) =>
          emit(state.copyWith(saving: false, users: _replaced(updated))),
    );
  }

  Future<void> setBlocked(int userId, bool blocked) async {
    if (state.saving) return;
    emit(state.copyWith(saving: true, actionFailure: null));
    final result = blocked
        ? await _users.block(userId)
        : await _users.unblock(userId);
    if (isClosed) return;

    result.match(
      (failure) => emit(state.copyWith(saving: false, actionFailure: failure)),
      (updated) =>
          emit(state.copyWith(saving: false, users: _replaced(updated))),
    );
  }

  Future<void> delete(int userId) async {
    if (state.saving) return;
    emit(state.copyWith(saving: true, actionFailure: null));
    final result = await _users.delete(userId);
    if (isClosed) return;

    result.match(
      (failure) => emit(state.copyWith(saving: false, actionFailure: failure)),
      (_) => emit(
        state.copyWith(
          saving: false,
          users: state.users.where((u) => u.id != userId).toList(),
        ),
      ),
    );
  }

  Future<void> grantRole({
    required int userId,
    required String role,
    required String scopeType,
    int? scopeId,
  }) async {
    if (state.saving) return;
    emit(state.copyWith(saving: true, actionFailure: null));
    final result = await _roleAssignments.grant(
      subjectType: 'user',
      subjectId: userId,
      role: role,
      scopeType: scopeType,
      scopeId: scopeId,
    );
    if (isClosed) return;

    await result.match(
      (failure) async =>
          emit(state.copyWith(saving: false, actionFailure: failure)),
      (_) async {
        emit(state.copyWith(saving: false));
        await loadRoleAssignments(userId);
      },
    );
  }

  Future<void> revokeRole(int assignmentId, int userId) async {
    if (state.saving) return;
    emit(state.copyWith(saving: true, actionFailure: null));
    final result = await _roleAssignments.revoke(assignmentId);
    if (isClosed) return;

    await result.match(
      (failure) async =>
          emit(state.copyWith(saving: false, actionFailure: failure)),
      (_) async {
        emit(state.copyWith(saving: false));
        await loadRoleAssignments(userId);
      },
    );
  }

  /// Resolves the "Область" picker in the role-grant form — a group or
  /// project by name, never by an id the reader is expected to know
  /// (`AdminSearchPicker`). A failed lookup degrades to an empty result list
  /// rather than surfacing [state.actionFailure]: a search box coming up
  /// empty reads as "no matches yet", not as a form-level error that would
  /// block the fields already filled in.
  Future<List<GroupDto>> searchGroups(String query) async {
    final result = await _resources.groups(name: query);
    return result.getOrElse((_) => const []);
  }

  Future<List<ProjectDto>> searchProjects(String query) async {
    final result = await _resources.searchProjects(name: query);
    return result.getOrElse((_) => const []);
  }

  /// `SoleOwnerConflictDialog`'s per-group «Выдать роль» — the recipient
  /// search its `GrantAccessDialog` needs, same as the group/project
  /// «Доступ» section's.
  Future<List<UserDto>> searchUsers(String query) =>
      _roleAssignments.searchUsers(query);

  /// `SoleOwnerConflictDialog`'s per-group «Выдать роль» — candidate teams
  /// for that one blocking group, narrowed by substring client-side, same
  /// idiom and same reasoning as `GroupDetailCubit.searchTeams`: the server
  /// has no `?name=` filter for a group's team list.
  Future<List<TeamDto>> searchTeamsOfGroup(int groupId, String query) async {
    final result = await _resources.teamsOf(groupId);
    final teams = result.getOrElse((_) => const []);
    if (query.isEmpty) return teams;
    final needle = query.toLowerCase();
    return [
      for (final team in teams)
        if (team.name.toLowerCase().contains(needle)) team,
    ];
  }

  /// `SoleOwnerConflictDialog`'s per-group «Выдать роль» — a grant on a
  /// group the deletion named as blocked, not on the subject being deleted.
  /// Deliberately outside [state.saving]/[actionFailure]: this dialog is its
  /// own short-lived flow, not part of the row's delete attempt, and mixing
  /// the two would make one's spinner cover the other's form.
  Future<Either<ApiFailure, RoleAssignmentDto>> grantAccessToGroup({
    required int groupId,
    required String subjectType,
    required int subjectId,
    required String role,
  }) {
    return _roleAssignments.grant(
      subjectType: subjectType,
      subjectId: subjectId,
      role: role,
      scopeType: 'group',
      scopeId: groupId,
    );
  }

  List<UserDto> _replaced(UserDto updated) => [
    for (final user in state.users)
      if (user.id == updated.id) updated else user,
  ];
}
