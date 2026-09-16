import 'package:cherrypick/cherrypick.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:structured_log_admin_client/features/audit/application/query_audit_log.dart';
import 'package:structured_log_admin_client/features/audit/domain/audit_filter.dart';
import 'package:structured_log_admin_client/features/audit/domain/audit_repository.dart';
import 'package:structured_log_admin_client/features/audit/infrastructure/audit_repository_impl.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_admin_client/features/audit/di/audit_module.dart';
import 'package:structured_log_admin_client/shared/api/api_client.dart';
import 'package:structured_log_admin_client/shared/api/api_failure.dart';
import 'package:structured_log_admin_client/shared/api/dto/audit_dto.dart';
import 'package:structured_log_admin_client/shared/auth/token_storage.dart';
import 'package:structured_log_admin_client/shared/config/app_config.dart';
import 'package:structured_log_admin_client/shared/di/app_module.dart';

import '../../shared/api/fake_adapter.dart';

const _config = AppConfig(baseUrl: 'https://logs.example.test');

const _page = {
  'items': [
    {
      'id': 42,
      'actor_user_id': 1,
      'action': 'group.created',
      'target_type': 'group',
      'target_id': 7,
      'metadata': <String, Object?>{},
      'created_at': '2026-09-16T08:14:02.000Z',
    },
  ],
  'next_cursor': '42',
  'audit_retention_days': 365,
  'auth_event_retention_days': 30,
};

class _RecordingRepository implements AuditRepository {
  final calls = <({AuditFilter filter, String? cursor, int? limit})>[];
  ApiFailure? refuse;

  @override
  Future<Either<ApiFailure, AuditPageDto>> query({
    AuditFilter filter = const AuditFilter(),
    String? cursor,
    int? limit,
  }) async {
    calls.add((filter: filter, cursor: cursor, limit: limit));
    final failure = refuse;
    return failure == null ? right(const AuditPageDto()) : left(failure);
  }
}

void main() {
  group('AuditFilter', () {
    test('an untouched filter is not narrowing anything', () {
      expect(const AuditFilter().isActive, isFalse);
    });

    test('any single field makes it active', () {
      // The screen tells "nothing matched these filters" from "nothing has
      // happened yet" by this flag alone, so a field that does not count here
      // would give a reader the wrong explanation for an empty page.
      expect(const AuditFilter(actorUserId: 1).isActive, isTrue);
      expect(const AuditFilter(action: 'group.created').isActive, isTrue);
      expect(const AuditFilter(targetType: 'group').isActive, isTrue);
      expect(const AuditFilter(targetId: 7).isActive, isTrue);
      expect(AuditFilter(from: DateTime.utc(2026, 9, 1)).isActive, isTrue);
      expect(AuditFilter(to: DateTime.utc(2026, 9, 16)).isActive, isTrue);
    });
  });

  group('AuditRepositoryImpl', () {
    ({AuditRepositoryImpl repository, FakeAdapter adapter}) build({
      FakeReply Function(RequestOptions)? answer,
    }) {
      final adapter = FakeAdapter(
        answer ?? (_) => const FakeReply(200, body: _page),
      );
      final client = ApiClient(
        config: _config,
        storage: InMemoryTokenStorage(),
        adapter: adapter,
      );
      return (repository: AuditRepositoryImpl(client), adapter: adapter);
    }

    test('every field of the filter reaches the wire', () async {
      final (:repository, :adapter) = build();

      final result = await repository.query(
        filter: AuditFilter(
          actorUserId: 1,
          action: 'project.quota_updated',
          targetType: 'project',
          targetId: 7,
          from: DateTime.utc(2026, 9, 1),
          to: DateTime.utc(2026, 9, 16),
        ),
        cursor: '99',
        limit: 25,
      );

      expect(result.isRight(), isTrue);
      expect(adapter.requests.single.uri.queryParameters, {
        'actor_user_id': '1',
        'action': 'project.quota_updated',
        'target_type': 'project',
        'target_id': '7',
        'from': '2026-09-01T00:00:00.000Z',
        'to': '2026-09-16T00:00:00.000Z',
        'cursor': '99',
        'limit': '25',
      });
    });

    test('a local time is converted, not sent as written', () async {
      // The server reads these as UTC. A bound sent in the reader's own offset
      // would move the window by hours without anyone being told.
      final (:repository, :adapter) = build();
      final local = DateTime(2026, 9, 1, 12);

      await repository.query(filter: AuditFilter(from: local));

      expect(
        adapter.requests.single.uri.queryParameters['from'],
        local.toUtc().toIso8601String(),
      );
    });

    test('an empty filter narrows nothing on the wire either', () async {
      final (:repository, :adapter) = build();

      await repository.query();

      expect(
        adapter.requests.single.uri.queryParameters,
        isEmpty,
        reason:
            'an empty `action=` is a filter the server would try to match, '
            'not the absence of one',
      );
    });

    test('a refusal comes back as a failure, not as a throw', () async {
      final (:repository, adapter: _) = build(
        answer: (_) => const FakeReply(403, body: {'error': 'forbidden'}),
      );

      final result = await repository.query();

      expect(result.isLeft(), isTrue);
    });
  });

  group('QueryAuditLog', () {
    test('the first page carries no cursor', () async {
      final repository = _RecordingRepository();

      await QueryAuditLog(
        repository,
      ).first(filter: const AuditFilter(action: 'group.created'));

      expect(repository.calls.single.cursor, isNull);
      expect(repository.calls.single.filter.action, 'group.created');
    });

    test('a further page repeats the filter alongside the cursor', () async {
      // The server re-applies the filter on every page. Paging with the cursor
      // but without the filter would widen the query halfway through, and the
      // reader would be shown records they had filtered out.
      final repository = _RecordingRepository();
      const filter = AuditFilter(action: 'auth.login_failed');

      await QueryAuditLog(repository).more(cursor: '41', filter: filter);

      expect(repository.calls.single.cursor, '41');
      expect(repository.calls.single.filter, filter);
    });
  });
  group('openAuditScope', () {
    test('the subscope composes the feature out of the shared client', () {
      // A module that never resolves is a feature that is tested and inert:
      // the screen would build, the scope would throw, and no unit test above
      // would have noticed. One resolution is what pins the wiring.
      CherryPick.closeRootScope();
      addTearDown(CherryPick.closeRootScope);

      final root = openAppScope(
        config: _config,
        logger: getLogger('test'),
        tokenStorage: InMemoryTokenStorage(),
        httpAdapter: FakeAdapter((_) => const FakeReply(200, body: _page)),
      );

      final scope = openAuditScope(root);

      expect(scope.resolve<QueryAuditLog>(), isNotNull);
      expect(
        scope.resolve<AuditRepository>(),
        same(scope.resolve<AuditRepository>()),
        reason: 'a singleton within the subscope, like every other repository',
      );
    });
  });
}
