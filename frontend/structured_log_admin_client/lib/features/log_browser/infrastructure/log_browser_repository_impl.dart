import 'package:dio/dio.dart';
import 'package:fpdart/fpdart.dart';

import '../../../shared/api/api_client.dart';
import '../../../shared/api/api_failure.dart';
import '../../../shared/api/dto/resource_dto.dart';
import '../../../shared/api/failure_mapper.dart';
import '../../../shared/api/logs_api.dart';
import '../domain/live_feed_event.dart';
import '../domain/log_browser_repository.dart';
import '../domain/log_filter.dart';
import '../domain/log_scope.dart';
import 'log_stream_client.dart';

class LogBrowserRepositoryImpl implements LogBrowserRepository {
  final ApiClient _api;

  /// The live half. Separate from [ApiClient] because it is the one endpoint
  /// written by hand rather than generated (design.md decision 37), even
  /// though it runs on the same `Dio` instance.
  final LogStreamClient _stream;

  const LogBrowserRepositoryImpl(this._api, this._stream);

  /// The server's own default, passed explicitly so a reader of this file
  /// does not have to know it to follow [loadMoreScopes].
  static const _scopePageSize = 50;

  @override
  Future<Either<ApiFailure, ScopeOptions>> loadScopes() async {
    try {
      // Both lists, because a role can be granted on either level and
      // neither list implies the other: a project-scoped user sees no groups
      // at all, a group-scoped one sees the group and its projects.
      final groups = await _api.groups.list(limit: _scopePageSize);
      final projects = await _api.projects.list(limit: _scopePageSize);
      return right(_options(groups: groups, projects: projects));
    } on DioException catch (error) {
      return left(mapDioException(error));
    }
  }

  @override
  Future<Either<ApiFailure, ScopeOptions>> loadMoreScopes({
    required bool groups,
    required String cursor,
  }) async {
    try {
      return right(
        groups
            ? _options(
                groups: await _api.groups.list(
                  limit: _scopePageSize,
                  cursor: cursor,
                ),
              )
            : _options(
                projects: await _api.projects.list(
                  limit: _scopePageSize,
                  cursor: cursor,
                ),
              ),
      );
    } on DioException catch (error) {
      return left(mapDioException(error));
    }
  }

  ScopeOptions _options({GroupListDto? groups, ProjectListDto? projects}) {
    return ScopeOptions(
      groups: [
        for (final group in groups?.items ?? const <GroupDto>[])
          GroupScope(id: group.id, name: group.name),
      ],
      projects: [
        for (final project in projects?.items ?? const <ProjectDto>[])
          ProjectScope(id: project.id, name: project.name),
      ],
      blockedProjectIds: {
        for (final project in projects?.items ?? const <ProjectDto>[])
          if (project.isBlocked) project.id,
      },
      groupsCursor: groups?.nextCursor,
      projectsCursor: projects?.nextCursor,
    );
  }

  @override
  Future<Either<ApiFailure, LogPage>> query({
    required LogScope scope,
    required LogFilter filter,
    String? cursor,
    int limit = 50,
  }) async {
    try {
      final page = await _api.logs.query(
        projectId: switch (scope) {
          ProjectScope(:final id) => id,
          GroupScope() => null,
        },
        groupId: switch (scope) {
          GroupScope(:final id) => id,
          ProjectScope() => null,
        },
        level: filter.minLevel,
        category: filter.category,
        logger: filter.logger,
        search: filter.search,
        // The server parses these as ISO 8601; sending local time would shift
        // the window by the operator's offset without saying so.
        from: filter.from?.toUtc().toIso8601String(),
        to: filter.to?.toUtc().toIso8601String(),
        sessionId: filter.sessionId,
        requestId: filter.requestId,
        toolCallId: filter.toolCallId,
        messageId: filter.messageId,
        operationId: filter.operationId,
        connectionGeneration: filter.connectionGeneration,
        cursor: cursor,
        limit: limit,
        contextFilters: filter.context.isEmpty
            ? null
            : contextQuery(filter.context),
      );
      return right((entries: page.items, nextCursor: page.nextCursor));
    } on DioException catch (error) {
      return left(mapDioException(error));
    }
  }

  @override
  Stream<LiveFeedEvent> watch({
    required LogScope scope,
    required LogFilter filter,
    int? sinceId,
  }) {
    return _stream.connect(scope: scope, filter: filter, sinceId: sinceId);
  }
}
