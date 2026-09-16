import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:structured_log_admin_client/features/audit/application/query_audit_log.dart';
import 'package:structured_log_admin_client/features/audit/domain/audit_filter.dart';
import 'package:structured_log_admin_client/features/audit/domain/audit_repository.dart';
import 'package:structured_log_admin_client/features/audit/presentation/audit_action_labels.dart';
import 'package:structured_log_admin_client/features/audit/presentation/audit_cubit.dart';
import 'package:structured_log_admin_client/features/audit/presentation/audit_failure_text.dart';
import 'package:structured_log_admin_client/features/audit/presentation/audit_metadata_view.dart';
import 'package:structured_log_admin_client/features/audit/presentation/audit_page.dart';
import 'package:structured_log_admin_client/shared/api/api_failure.dart';
import 'package:structured_log_admin_client/shared/api/dto/audit_dto.dart';
import 'package:structured_log_admin_ui/structured_log_admin_ui.dart';

AuditEntryDto _entry({
  int id = 1,
  int? actorUserId = 1,
  String action = 'group.created',
  String targetType = 'group',
  int? targetId = 7,
  Map<String, dynamic> metadata = const {},
  DateTime? createdAt,
}) => AuditEntryDto(
  id: id,
  actorUserId: actorUserId,
  action: action,
  targetType: targetType,
  targetId: targetId,
  metadata: metadata,
  createdAt: createdAt ?? DateTime.utc(2026, 9, 13, 9, 41),
);

class _FakeRepository implements AuditRepository {
  var pages = <AuditPageDto>[const AuditPageDto()];
  ApiFailure? refuse;
  final calls = <({AuditFilter filter, String? cursor})>[];

  @override
  Future<Either<ApiFailure, AuditPageDto>> query({
    AuditFilter filter = const AuditFilter(),
    String? cursor,
    int? limit,
  }) async {
    calls.add((filter: filter, cursor: cursor));
    final failure = refuse;
    if (failure != null) return left(failure);
    return right(pages[calls.length.clamp(1, pages.length) - 1]);
  }
}

void main() {
  group('audit action vocabulary', () {
    test('every action has a name of its own', () {
      // The switch is exhaustive, so the compiler already guarantees a branch
      // per action. What it cannot catch is an empty or duplicated one, which
      // would leave two different records reading identically in the menu.
      final labels = AuditAction.values.map(auditActionLabel).toList();

      expect(labels.every((label) => label.isNotEmpty), isTrue);
      expect(labels.toSet(), hasLength(AuditAction.values.length));
    });

    test('the wire strings match the published set', () {
      // A typo here matches nothing on the server rather than failing, and a
      // filter that silently matches nothing is the one wrong answer an audit
      // log must not give.
      expect(AuditAction.values.map((a) => a.wire), [
        'user.created',
        'user.updated',
        'user.blocked',
        'user.unblocked',
        'user.deleted',
        'group.created',
        'team.created',
        'team.member_added',
        'team.member_removed',
        'project.created',
        'project.quota_updated',
        'project.blocked',
        'project.unblocked',
        'secret_key.created',
        'secret_key.revoked',
        'role_assignment.created',
        'role_assignment.revoked',
        'password.changed',
        'password.reset_confirmed',
        'email.verified',
        'auth.login_succeeded',
        'auth.login_failed',
        'auth.logged_out',
        'auth.throttled',
        'audit.purged',
      ]);
      expect(
        AuditAction.values.where((a) => a.isAuthEvent).map((a) => a.wire),
        [
          'auth.login_succeeded',
          'auth.login_failed',
          'auth.logged_out',
          'auth.throttled',
        ],
      );
    });

    test('losing access reads red, regaining it green', () {
      expect(
        auditActionTone(AuditAction.projectBlocked),
        AdminStatusTone.error,
      );
      expect(
        auditActionTone(AuditAction.projectUnblocked),
        AdminStatusTone.success,
      );
      expect(
        auditActionTone(AuditAction.authThrottled),
        AdminStatusTone.warning,
      );
      expect(
        auditActionTone(AuditAction.groupCreated),
        AdminStatusTone.neutral,
      );
    });

    test('an action this build does not know is still readable', () {
      expect(AuditAction.fromWire('user.renamed'), isNull);
    });
  });

  group('actor and target', () {
    test('a record with an actor shows its id', () {
      expect(auditActorText(_entry()).text, '#1');
      expect(auditActorText(_entry()).absent, isFalse);
    });

    test('an attempt under a username that does not exist says so', () {
      // Not an empty id, and no request to resolve a name — there is no
      // account to resolve (`specs/admin-client-audit-log`).
      final actor = auditActorText(
        _entry(
          actorUserId: null,
          action: 'auth.login_failed',
          metadata: const {'unknown_user': true, 'reason': 'unknown_user'},
        ),
      );

      expect(actor.text, 'учётной записи не существует');
      expect(actor.absent, isTrue);
    });

    test('a record the server wrote about itself names the server', () {
      final actor = auditActorText(
        _entry(actorUserId: null, action: 'audit.purged', targetType: 'audit'),
      );

      expect(actor.text, 'сервер');
      expect(actor.absent, isTrue);
    });

    test('a target is its kind and its id, or its kind alone', () {
      expect(auditTargetText(_entry()), 'группа #7');
      expect(
        auditTargetText(_entry(targetType: 'auth', targetId: null)),
        'аутентификация',
      );
    });
  });

  group('readableMetadata', () {
    test('a quota change reads as what moved', () {
      final details = readableMetadata(const {
        'before': {'retention_days': 30, 'max_entries': 2000},
        'after': {'retention_days': 30, 'max_entries': null},
      });

      expect(details, hasLength(1), reason: 'retention_days did not move');
      expect(details.single.key, 'max_entries');
      expect(
        details.single.value,
        '2000 → без лимита',
        reason: 'a null limit inside a quota is a stated value, not a gap',
      );
    });

    test('a call that changed nothing says so rather than showing empty', () {
      final details = readableMetadata(const {
        'before': {'retention_days': 30},
        'after': {'retention_days': 30},
      });

      expect(details.single.value, 'нет');
    });

    test('flat keys keep their order and their booleans read in words', () {
      final details = readableMetadata(const {
        'reason': 'invalid_password',
        'client_ip': '203.0.113.7',
        'unknown_user': true,
        'user_agent': null,
      });

      expect(details.map((d) => d.key), [
        'reason',
        'client_ip',
        'unknown_user',
        'user_agent',
      ]);
      expect(details[2].value, 'да');
      expect(details[3].value, '—');
    });

    test('a nested object is flattened, not stringified', () {
      final details = readableMetadata(const {
        'quota': {'max_entries': 1000},
      });

      expect(details.single.key, 'quota.max_entries');
      expect(details.single.value, '1000');
    });
  });

  group('describeRetention', () {
    test('no limit is said in words, not as a number', () {
      expect(describeRetention(null), 'без ограничения срока');
    });

    test('a period agrees with its number', () {
      expect(describeRetention(1), '1 день');
      expect(describeRetention(3), '3 дня');
      expect(describeRetention(11), '11 дней');
      expect(describeRetention(21), '21 день');
      expect(describeRetention(365), '365 дней');
    });
  });

  group('timestamps', () {
    test('a time is local, padded and unambiguous', () {
      // Local, because the reader is looking for something that happened to
      // them. Constructed as local here rather than as UTC so the assertion
      // holds wherever the test runs — CI is UTC and a developer is not.
      final local = DateTime(2026, 9, 3, 9, 5);

      expect(formatAuditTime(local.toUtc()), '03.09.2026 09:05');
      expect(formatAuditDate(local.toUtc()), '03 сен');
    });
  });

  group('AuditCubit', () {
    test('a first page fills the list and remembers the retention', () async {
      final repository = _FakeRepository()
        ..pages = [
          AuditPageDto(
            items: [_entry()],
            nextCursor: '1',
            auditRetentionDays: 365,
            authEventRetentionDays: 90,
          ),
        ];
      final cubit = AuditCubit(QueryAuditLog(repository));
      addTearDown(cubit.close);

      await cubit.load();

      expect(cubit.state.entries, hasLength(1));
      expect(cubit.state.hasMore, isTrue);
      expect(cubit.state.auditRetentionDays, 365);
      expect(cubit.state.authEventRetentionDays, 90);
      expect(cubit.state.loaded, isTrue);
    });

    test('a further page is appended, not substituted', () async {
      final repository = _FakeRepository()
        ..pages = [
          AuditPageDto(items: [_entry(id: 2)], nextCursor: '2'),
          AuditPageDto(items: [_entry(id: 1)]),
        ];
      final cubit = AuditCubit(QueryAuditLog(repository));
      addTearDown(cubit.close);

      await cubit.load();
      await cubit.loadMore();

      expect(cubit.state.entries.map((e) => e.id), [2, 1]);
      expect(cubit.state.hasMore, isFalse);
      expect(repository.calls.last.cursor, '2');
    });

    test('a changed filter starts over rather than paging on', () async {
      // The cursor belongs to the query that produced it. Carrying it across a
      // changed filter would page through a question nobody asked.
      final repository = _FakeRepository()
        ..pages = [
          AuditPageDto(items: [_entry(id: 2)], nextCursor: '2'),
          const AuditPageDto(),
        ];
      final cubit = AuditCubit(QueryAuditLog(repository));
      addTearDown(cubit.close);

      await cubit.load();
      await cubit.applyFilter(
        const AuditFilter(action: AuditAction.authLoginFailed),
      );

      expect(repository.calls.last.cursor, isNull);
      expect(repository.calls.last.filter.action, AuditAction.authLoginFailed);
      expect(cubit.state.entries, isEmpty);
    });

    test('a refusal is kept and the list is left alone', () async {
      final repository = _FakeRepository()
        ..refuse = const ForbiddenFailure(code: 'forbidden');
      final cubit = AuditCubit(QueryAuditLog(repository));
      addTearDown(cubit.close);

      await cubit.load();

      expect(cubit.state.failure, isA<ForbiddenFailure>());
      expect(cubit.state.loading, isFalse);
      expect(cubit.state.loaded, isFalse);
    });

    test('an empty range inside the retention is about the filters', () {
      final state = AuditState(
        loading: false,
        loaded: true,
        filter: AuditFilter(
          from: DateTime.now().subtract(const Duration(days: 5)),
        ),
        auditRetentionDays: 365,
        authEventRetentionDays: 90,
      );

      expect(state.isEmpty, isTrue);
      expect(state.isEmptyByRetention, isFalse);
    });

    test('an empty range older than the shorter period blames retention', () {
      // The earlier of the two cutoffs is the one that can have removed what
      // the reader is looking for, so 100 days back is already past the
      // 90-day auth period even though administrative acts are kept a year.
      final state = AuditState(
        loading: false,
        loaded: true,
        filter: AuditFilter(
          from: DateTime.now().subtract(const Duration(days: 100)),
        ),
        auditRetentionDays: 365,
        authEventRetentionDays: 90,
      );

      expect(state.isEmptyByRetention, isTrue);
    });

    test('retention switched off never blames retention', () {
      final state = AuditState(
        loading: false,
        loaded: true,
        filter: AuditFilter(from: DateTime.utc(2000)),
      );

      expect(state.isEmptyByRetention, isFalse);
    });
  });

  group('AuditPage', () {
    Widget host(AuditCubit cubit) => FluentApp(
      theme: AdminTheme.light(),
      home: ScaffoldPage(
        padding: EdgeInsets.zero,
        content: BlocProvider.value(value: cubit, child: const AuditPage()),
      ),
    );

    testWidgets('a record shows its time, actor, action, target and details', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repository = _FakeRepository()
        ..pages = [
          AuditPageDto(
            items: [
              _entry(
                action: 'project.quota_updated',
                targetType: 'project',
                metadata: const {
                  'before': {'max_entries': 2000},
                  'after': {'max_entries': null},
                },
              ),
            ],
            auditRetentionDays: 365,
            authEventRetentionDays: 90,
          ),
        ];
      final cubit = AuditCubit(QueryAuditLog(repository));
      addTearDown(cubit.close);

      await tester.pumpWidget(host(cubit));
      await cubit.load();
      await tester.pumpAndSettle();

      expect(
        find.text(formatAuditTime(DateTime.utc(2026, 9, 13, 9, 41))),
        findsOneWidget,
        reason:
            'the timestamp is rendered in local time — the literal is not '
            'written out here because it would pin the test to one offset',
      );
      expect(find.text('#1'), findsOneWidget);
      expect(find.text('project.quota_updated'), findsOneWidget);
      expect(find.text('проект #7'), findsOneWidget);
      expect(find.text('Административные действия: 365 дней'), findsOneWidget);
      expect(find.text('События аутентификации: 90 дней'), findsOneWidget);
    });

    testWidgets('an empty result outside the retention names both periods', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repository = _FakeRepository()
        ..pages = [
          const AuditPageDto(
            auditRetentionDays: 365,
            authEventRetentionDays: 90,
          ),
        ];
      final cubit = AuditCubit(QueryAuditLog(repository));
      addTearDown(cubit.close);

      await tester.pumpWidget(host(cubit));
      await cubit.load();
      await cubit.applyFilter(
        AuditFilter(from: DateTime.now().subtract(const Duration(days: 200))),
      );
      await tester.pumpAndSettle();

      expect(find.text('Записи за этот период уже удалены'), findsOneWidget);
      expect(
        find.textContaining('хранятся 90 дней'),
        findsOneWidget,
        reason: 'both periods are named, not reduced to one',
      );
      expect(find.textContaining('действия — 365 дней'), findsOneWidget);
    });

    testWidgets('a refusal is explained as a refusal, not as a failed load', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repository = _FakeRepository()
        ..refuse = const ForbiddenFailure(code: 'forbidden');
      final cubit = AuditCubit(QueryAuditLog(repository));
      addTearDown(cubit.close);

      await tester.pumpWidget(host(cubit));
      await cubit.load();
      await tester.pumpAndSettle();

      expect(
        find.textContaining('доступен только администратору'),
        findsWidgets,
      );
    });

    testWidgets('another page is offered only while there is one', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repository = _FakeRepository()
        ..pages = [
          AuditPageDto(items: [_entry(id: 2)], nextCursor: '2'),
          AuditPageDto(items: [_entry(id: 1)]),
        ];
      final cubit = AuditCubit(QueryAuditLog(repository));
      addTearDown(cubit.close);

      await tester.pumpWidget(host(cubit));
      await cubit.load();
      await tester.pumpAndSettle();
      expect(find.text('Показать ещё'), findsOneWidget);

      await tester.tap(find.text('Показать ещё'));
      await tester.pumpAndSettle();

      expect(cubit.state.entries, hasLength(2));
      expect(find.text('Показать ещё'), findsNothing);
    });
  });
}
