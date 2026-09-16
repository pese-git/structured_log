import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../shared/api/api_failure.dart';
import '../../../shared/api/dto/resource_dto.dart';
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
  }) = _ProjectDetailState;

  const ProjectDetailState._();

  /// Loaded, and this project has never had a key.
  bool get hasNoKeys => !loading && keys.isEmpty;
}

class ProjectDetailCubit extends Cubit<ProjectDetailState> {
  final ManageProjects _projects;
  final ManageSecretKeys _keys;
  final int projectId;

  ProjectDetailCubit({
    required ManageProjects projects,
    required ManageSecretKeys keys,
    required this.projectId,
  }) : _projects = projects,
       _keys = keys,
       super(const ProjectDetailState());

  Future<void> load() async {
    emit(state.copyWith(loading: true, failure: null));
    // Both, because the screen is not useful with either half missing: the
    // quota comes from the project, the keys from their own endpoint.
    final project = await _projects.get(projectId);
    final keys = await _keys.list(projectId);
    if (isClosed) return;

    project.match(
      (failure) => emit(state.copyWith(loading: false, failure: failure)),
      (project) => emit(
        state.copyWith(
          loading: false,
          project: project,
          keys: keys.getOrElse((_) => const []),
          failure: null,
        ),
      ),
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

  Future<void> _reloadKeys() async {
    final keys = await _keys.list(projectId);
    if (isClosed) return;
    keys.match((_) {}, (keys) => emit(state.copyWith(keys: keys)));
  }
}
