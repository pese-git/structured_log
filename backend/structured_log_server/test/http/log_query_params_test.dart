import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:structured_log_server/src/auth/identity_provider.dart';
import 'package:structured_log_server/src/errors.dart';
import 'package:structured_log_server/src/http/log_query_params.dart';
import 'package:structured_log_server/src/rbac/authorizer.dart';
import 'package:structured_log_server/src/storage/database.dart';
import 'package:test/test.dart';

StructuredLogDatabase openInMemory() {
  return StructuredLogDatabase(
    NativeDatabase.memory(setup: (db) => db.execute('PRAGMA foreign_keys=ON;')),
  );
}

Matcher throwsApiError(int statusCode, [String? code]) {
  var matcher = isA<ApiError>().having(
    (e) => e.statusCode,
    'status',
    statusCode,
  );
  if (code != null) matcher = matcher.having((e) => e.code, 'code', code);
  return throwsA(matcher);
}

const _admin = [EffectiveRole(role: Role.admin, scopeType: ScopeType.global)];

void main() {
  group('parseLogFilter', () {
    test('an absent parameter leaves the corresponding field unset', () {
      final filter = parseLogFilter(const {});
      expect(filter.minLevel, isNull);
      expect(filter.category, isNull);
      expect(filter.contextEquals, isEmpty);
    });

    test('maps every documented query parameter onto its field', () {
      final filter = parseLogFilter(const {
        'level': 'warning',
        'category': 'payments',
        'logger': 'checkout',
        'session_id': 's',
        'request_id': 'r',
        'connection_generation': '3',
        'tool_call_id': 't',
        'message_id': 'm',
        'operation_id': 'o',
        'q': 'text',
      });

      expect(filter.minLevel, 'warning');
      expect(filter.category, 'payments');
      expect(filter.logger, 'checkout');
      expect(filter.sessionId, 's');
      expect(filter.requestId, 'r');
      expect(filter.connectionGeneration, 3);
      expect(filter.toolCallId, 't');
      expect(filter.messageId, 'm');
      expect(filter.operationId, 'o');
      expect(filter.q, 'text');
    });

    test('collects context.* into contextEquals, stripping the prefix', () {
      final filter = parseLogFilter(const {
        'context.user_id': '42',
        'context.tenant': 'acme',
        'category': 'not-context',
      });

      expect(filter.contextEquals, {'user_id': '42', 'tenant': 'acme'});
    });

    test('ignores scope and pagination parameters', () {
      // Scope is authorized separately and pagination belongs to the
      // historical query; neither may leak into a filter that the live
      // stream also applies.
      final filter = parseLogFilter(const {
        'project_id': '1',
        'group_id': '2',
        'limit': '10',
        'cursor': '5',
        'since_id': '3',
      });

      expect(filter.contextEquals, isEmpty);
      expect(filter.minLevel, isNull);
      expect(filter.q, isNull);
    });

    test('rejects an unknown level with 400 instead of ignoring it', () {
      // Treating it as "no filter" would hand back entries the caller
      // explicitly asked to exclude. Before this was validated, the same
      // input reached `sublist(-1)` and answered 500.
      expect(
        () => parseLogFilter(const {'level': 'bogus'}),
        throwsApiError(400, 'invalid_request'),
      );
      expect(
        () => parseLogFilter(const {'level': 'INFO'}),
        throwsApiError(400, 'invalid_request'),
        reason: 'levels are lower-case',
      );
    });

    test('accepts every level the server knows', () {
      for (final level in [
        'trace',
        'debug',
        'info',
        'warning',
        'error',
        'critical',
      ]) {
        expect(parseLogFilter({'level': level}).minLevel, level);
      }
    });

    test('an unparsable connection_generation is dropped, not fatal', () {
      // Unlike level, this can't silently widen the result set into
      // something the caller excluded: it is an equality filter, and a
      // dropped one can only return more of what was asked for.
      expect(
        parseLogFilter(const {
          'connection_generation': 'x',
        }).connectionGeneration,
        isNull,
      );
    });
  });

  group('resolveLogScope', () {
    late StructuredLogDatabase db;
    late Authorizer authorizer;
    late int groupId;
    late int projectId;
    late int blockedId;

    VerifiedIdentity identity([List<EffectiveRole> roles = _admin]) =>
        VerifiedIdentity(userId: 1, username: 'u', roles: roles);

    setUp(() async {
      db = openInMemory();
      authorizer = Authorizer(db);
      groupId = await db
          .into(db.groups)
          .insert(GroupsCompanion.insert(name: 'g'));
      projectId = await db
          .into(db.projects)
          .insert(
            ProjectsCompanion.insert(
              groupId: groupId,
              name: 'open',
              retentionDays: 30,
            ),
          );
      blockedId = await db
          .into(db.projects)
          .insert(
            ProjectsCompanion.insert(
              groupId: groupId,
              name: 'blocked',
              retentionDays: 30,
              isBlocked: const Value(true),
            ),
          );
    });
    tearDown(() => db.close());

    test('requires exactly one of project_id and group_id', () async {
      expect(
        () => resolveLogScope(db, authorizer, identity(), const {}),
        throwsApiError(400, 'invalid_request'),
      );
      expect(
        () => resolveLogScope(db, authorizer, identity(), {
          'project_id': '$projectId',
          'group_id': '$groupId',
        }),
        throwsApiError(400, 'invalid_request'),
      );
    });

    test('a project scope resolves to just that project', () async {
      final scope = await resolveLogScope(db, authorizer, identity(), {
        'project_id': '$projectId',
      });

      expect(scope.projectIds, [projectId]);
      expect(scope.projectId, projectId);
      expect(scope.groupId, isNull);
    });

    test('a group scope resolves to its unblocked projects', () async {
      final scope = await resolveLogScope(db, authorizer, identity(), {
        'group_id': '$groupId',
      });

      expect(scope.projectIds, [projectId]);
      expect(scope.projectIds, isNot(contains(blockedId)));
      expect(scope.groupId, groupId);
      expect(scope.projectId, isNull);
    });

    test(
      'a blocked project requested directly is 403 project_blocked',
      () async {
        // Directly and silently differ on purpose: asking for a blocked
        // project is a mistake worth reporting, while a blocked project
        // inside a group is simply not part of the answer.
        expect(
          () => resolveLogScope(db, authorizer, identity(), {
            'project_id': '$blockedId',
          }),
          throwsApiError(403, 'project_blocked'),
        );
      },
    );

    test('an unknown or unparsable id is 404', () async {
      for (final params in [
        {'project_id': '999999'},
        {'project_id': 'abc'},
        {'group_id': '999999'},
        {'group_id': 'abc'},
      ]) {
        expect(
          () => resolveLogScope(db, authorizer, identity(), params),
          throwsApiError(404, 'not_found'),
          reason: '$params',
        );
      }
    });

    test('a caller without a covering role is 403', () async {
      expect(
        () => resolveLogScope(db, authorizer, identity(const []), {
          'project_id': '$projectId',
        }),
        throwsApiError(403, 'forbidden'),
      );
      expect(
        () => resolveLogScope(db, authorizer, identity(const []), {
          'group_id': '$groupId',
        }),
        throwsApiError(403, 'forbidden'),
      );
    });

    test('a role on another group does not open this one', () async {
      final elsewhere = [
        EffectiveRole(
          role: Role.owner,
          scopeType: ScopeType.group,
          scopeId: groupId + 1000,
        ),
      ];

      expect(
        () => resolveLogScope(db, authorizer, identity(elsewhere), {
          'group_id': '$groupId',
        }),
        throwsApiError(403, 'forbidden'),
      );
    });

    test(
      'a group with no readable projects resolves to an empty scope',
      () async {
        final emptyGroup = await db
            .into(db.groups)
            .insert(GroupsCompanion.insert(name: 'e'));

        final scope = await resolveLogScope(db, authorizer, identity(), {
          'group_id': '$emptyGroup',
        });

        expect(scope.projectIds, isEmpty);
        expect(scope.groupId, emptyGroup);
      },
    );
  });
}
