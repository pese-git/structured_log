import 'package:freezed_annotation/freezed_annotation.dart';

part 'log_scope.freezed.dart';

/// Exactly one project or exactly one group — never both, never an aggregate
/// across several (`specs/admin-client-log-browser`, `log-server-api`).
///
/// Modelled as a union rather than two nullable ids so "neither" and "both"
/// cannot be represented at all; the server refuses both cases with 400, and
/// a shape that can express them only moves the failure later.
@freezed
sealed class LogScope with _$LogScope {
  const factory LogScope.project({required int id, required String name}) =
      ProjectScope;

  const factory LogScope.group({required int id, required String name}) =
      GroupScope;
}

/// What the scope selector has to offer.
///
/// Both lists come from what the caller may actually read; the server decides
/// that, and the client shows only what it was given.
@freezed
abstract class ScopeOptions with _$ScopeOptions {
  const factory ScopeOptions({
    @Default(<GroupScope>[]) List<GroupScope> groups,
    @Default(<ProjectScope>[]) List<ProjectScope> projects,

    /// Projects the server reports as blocked. Offered but marked: they
    /// answer 403 to a log query, and hiding them would read as deletion.
    @Default(<int>{}) Set<int> blockedProjectIds,
  }) = _ScopeOptions;

  const ScopeOptions._();

  bool get isEmpty => groups.isEmpty && projects.isEmpty;
}
