import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:structured_log_admin_client/features/resources/application/manage_resources.dart';
import 'package:structured_log_admin_client/features/resources/domain/resources_repository.dart';
import 'package:structured_log_admin_client/features/resources/presentation/group_detail_cubit.dart';
import 'package:structured_log_admin_client/features/resources/presentation/group_detail_page.dart';
import 'package:structured_log_admin_client/features/resources/presentation/groups_cubit.dart';
import 'package:structured_log_admin_client/features/resources/presentation/groups_page.dart';
import 'package:structured_log_admin_client/features/resources/presentation/project_detail_cubit.dart';
import 'package:structured_log_admin_client/features/resources/presentation/project_detail_page.dart';
import 'package:structured_log_admin_client/features/role_assignments/application/manage_role_assignments.dart';
import 'package:structured_log_admin_client/features/role_assignments/domain/role_assignments_repository.dart';
import 'package:structured_log_admin_client/shared/api/api_failure.dart';
import 'package:structured_log_admin_client/shared/api/dto/resource_dto.dart';
import 'package:structured_log_admin_client/shared/api/dto/user_dto.dart';

import '../../support/localized_app.dart';
import 'package:structured_log_admin_client/shared/api/cursor_page.dart';
import '../../support/paging.dart';

/// The screens, driven through the widgets rather than the cubits.
///
/// Text entry is the reason these exist separately: it is the one thing a
/// browser cannot be made to do to a Flutter web canvas
/// (`reference_flutter_web_visual_check`), so the create flows — a group's
/// name, a key's label, and the reveal that follows — can only be exercised
/// here.
class _FakeRepository implements ResourcesRepository {
  var groupList = <GroupDto>[];
  var keyList = <SecretKeyDto>[];
  ProjectDto one = ProjectDto(
    id: 1,
    groupId: 1,
    name: 'checkout',
    retentionDays: 30,
    maxEntries: 1000,
    isBlocked: false,
    createdAt: DateTime.utc(2026, 2, 14),
    entryCount: 842,
    totalBytes: 5 * 1024 * 1024,
  );

  ApiFailure? refuseWrites;
  final created = <String>[];
  var projectList = <ProjectDto>[];

  @override
  Future<Either<ApiFailure, CursorPage<GroupDto>>> groups({
    String? name,
    int? limit,
    String? cursor,
  }) async => right(pageOf(groupList, limit: limit, cursor: cursor));

  @override
  Future<Either<ApiFailure, GroupDto>> createGroup(String name) async {
    created.add(name);
    if (refuseWrites != null) return left(refuseWrites!);
    final group = GroupDto(
      id: groupList.length + 1,
      name: name,
      createdAt: DateTime.utc(2026, 2, 14),
    );
    groupList = [...groupList, group];
    return right(group);
  }

  @override
  Future<Either<ApiFailure, CursorPage<ProjectDto>>> projectsOf(
    int groupId, {
    int? limit,
    String? cursor,
  }) async => right(pageOf(projectList, limit: limit, cursor: cursor));

  @override
  Future<Either<ApiFailure, CursorPage<ProjectDto>>> searchProjects({
    String? name,
    int? limit,
    String? cursor,
  }) async => right(pageOf(projectList, limit: limit, cursor: cursor));

  @override
  Future<Either<ApiFailure, ProjectDto>> project(int projectId) async =>
      right(one);

  @override
  Future<Either<ApiFailure, ProjectDto>> createProject({
    required int groupId,
    required String name,
    required int retentionDays,
    int? maxEntries,
    int? maxBytes,
  }) async => right(one);

  @override
  Future<Either<ApiFailure, ProjectDto>> updateQuota({
    required int projectId,
    required int retentionDays,
    required int? maxEntries,
    required int? maxBytes,
  }) async => right(one);

  @override
  Future<Either<ApiFailure, List<SecretKeyDto>>> secretKeys(
    int projectId,
  ) async => right(keyList);

  @override
  Future<Either<ApiFailure, SecretKeyDto>> createSecretKey({
    required int projectId,
    required String label,
  }) async {
    created.add(label);
    final key = SecretKeyDto(
      id: keyList.length + 1,
      projectId: projectId,
      label: label,
      createdAt: DateTime.utc(2026, 2, 14),
      secret: 'slk_shown_once',
    );
    keyList = [
      ...keyList,
      SecretKeyDto(
        id: key.id,
        projectId: projectId,
        label: label,
        createdAt: key.createdAt,
      ),
    ];
    return right(key);
  }

  @override
  Future<Either<ApiFailure, Unit>> revokeSecretKey({
    required int projectId,
    required int keyId,
  }) async => right(unit);

  @override
  Future<Either<ApiFailure, ProjectDto>> blockProject(int projectId) async =>
      right(one.copyWith(isBlocked: true));

  @override
  Future<Either<ApiFailure, ProjectDto>> unblockProject(int projectId) async =>
      right(one.copyWith(isBlocked: false));

  @override
  Future<Either<ApiFailure, List<TeamDto>>> teamsOf(int groupId) async =>
      right(const []);

  @override
  Future<Either<ApiFailure, TeamDto>> createTeam({
    required int groupId,
    required String name,
  }) async => right(
    TeamDto(
      id: 1,
      groupId: groupId,
      name: name,
      createdAt: DateTime.utc(2026, 2, 14),
    ),
  );

  @override
  Future<Either<ApiFailure, List<TeamMemberDto>>> teamMembers(
    int teamId,
  ) async => right(const []);

  @override
  Future<Either<ApiFailure, Unit>> addTeamMember({
    required int teamId,
    required int userId,
  }) async => right(unit);

  @override
  Future<Either<ApiFailure, Unit>> removeTeamMember({
    required int teamId,
    required int userId,
  }) async => right(unit);
}

/// These screens' `load()` calls `forScope` for the «Доступ» section — an
/// empty [forScopeResult] is enough to keep `load()` from throwing when a
/// test doesn't drive that section at all.
class _FakeRoleAssignments implements RoleAssignmentsRepository {
  var forScopeResult = <RoleAssignmentDto>[];
  ApiFailure? refuseWrites;

  @override
  Future<Either<ApiFailure, List<RoleAssignmentDto>>> forScope({
    required String scopeType,
    required int scopeId,
  }) async => right(forScopeResult);

  @override
  Future<Either<ApiFailure, Unit>> revoke(int assignmentId) async {
    if (refuseWrites != null) return left(refuseWrites!);
    return right(unit);
  }

  @override
  Never noSuchMethod(Invocation invocation) => throw UnimplementedError(
    '${invocation.memberName} is not used by resources_screens_test.dart',
  );
}

Widget _host(Widget child, {Locale locale = const Locale('ru')}) =>
    localizedApp(
      locale: locale,
      home: ScaffoldPage(padding: EdgeInsets.zero, content: child),
    );

void main() {
  late _FakeRepository repository;
  late _FakeRoleAssignments roleAssignmentsFake;
  late ManageRoleAssignments roleAssignments;

  setUp(() {
    repository = _FakeRepository();
    roleAssignmentsFake = _FakeRoleAssignments();
    roleAssignments = ManageRoleAssignments(roleAssignmentsFake);
  });

  void useWideSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  group('groups', () {
    Future<GroupsCubit> pump(WidgetTester tester) async {
      useWideSurface(tester);
      final cubit = GroupsCubit(ManageGroups(repository))..load();
      addTearDown(cubit.close);
      await tester.pumpWidget(
        _host(
          BlocProvider.value(
            value: cubit,
            child: GroupsPage(onOpen: (_) {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return cubit;
    }

    testWidgets('an empty list invites the first group', (tester) async {
      await pump(tester);

      expect(find.text('Групп пока нет'), findsOneWidget);
    });

    testWidgets('the English locale shows English text, not Russian', (
      tester,
    ) async {
      useWideSurface(tester);
      final cubit = GroupsCubit(ManageGroups(repository))..load();
      addTearDown(cubit.close);
      await tester.pumpWidget(
        _host(
          BlocProvider.value(
            value: cubit,
            child: GroupsPage(onOpen: (_) {}),
          ),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No groups yet'), findsOneWidget);
      expect(find.text('Create group'), findsOneWidget);
      expect(find.text('Групп пока нет'), findsNothing);
    });

    testWidgets('a name typed into the dialog creates the group', (
      tester,
    ) async {
      await pump(tester);

      await tester.tap(find.text('Создать группу'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextBox).first, 'payments');
      await tester.tap(find.text('Создать группу').last);
      await tester.pumpAndSettle();

      expect(repository.created, ['payments']);
      expect(
        find.text('payments'),
        findsOneWidget,
        reason: 'the dialog closes itself and the reloaded list shows it',
      );
    });

    testWidgets('a refusal is explained inside the dialog', (tester) async {
      repository.refuseWrites = const ApiFailure.forbidden(code: 'forbidden');
      await pump(tester);

      await tester.tap(find.text('Создать группу'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextBox).first, 'payments');
      await tester.tap(find.text('Создать группу').last);
      await tester.pumpAndSettle();

      expect(find.textContaining('Недостаточно прав'), findsOneWidget);
      expect(
        find.text('Название группы'),
        findsOneWidget,
        reason:
            'the dialog stays open so the reason is read where the '
            'attempt was made',
      );
    });
  });

  group('one project', () {
    Future<ProjectDetailCubit> pump(
      WidgetTester tester, {
      bool isAdmin = false,
    }) async {
      useWideSurface(tester);
      final cubit = ProjectDetailCubit(
        projects: ManageProjects(repository),
        keys: ManageSecretKeys(repository),
        roleAssignments: roleAssignments,
        teams: ManageTeams(repository),
        projectId: 1,
      )..load();
      addTearDown(cubit.close);
      await tester.pumpWidget(
        _host(
          BlocProvider.value(
            value: cubit,
            child: ProjectDetailPage(
              groupName: 'payments',
              isAdmin: isAdmin,
              onBackToGroups: () {},
              onOpenLogs: (_, _) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return cubit;
    }

    testWidgets('usage is shown beside its limit, never alone', (tester) async {
      await pump(tester);

      // "842 / 1 000" — the scenario in the spec, with a non-breaking space
      // inside the number.
      expect(find.textContaining('842'), findsOneWidget);
      expect(find.textContaining('1\u00A0000'), findsOneWidget);
      expect(find.text('30 дней'), findsOneWidget);
    });

    testWidgets('an unlimited quota says so instead of showing a bar', (
      tester,
    ) async {
      await pump(tester);

      // max_bytes is unset on the fixture: the usage is stated, the limit is
      // not invented.
      expect(find.textContaining('5\u00A0МБ'), findsOneWidget);
    });

    testWidgets('a created key is revealed once and then forgotten', (
      tester,
    ) async {
      final cubit = await pump(tester);
      expect(find.text('Секретных ключей пока нет'), findsOneWidget);

      await tester.tap(find.text('Создать ключ'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextBox).first, 'ci');
      await tester.tap(find.text('Создать ключ').last);
      await tester.pumpAndSettle();

      expect(find.text('Ключ создан'), findsOneWidget);
      expect(find.text('slk_shown_once'), findsOneWidget);
      expect(
        find.textContaining('только один раз'),
        findsOneWidget,
        reason:
            'the value cannot be retrieved again, and the dialog has to '
            'say so before it is closed',
      );

      await tester.tap(find.text('Я сохранил(а) ключ — закрыть'));
      await tester.pumpAndSettle();

      expect(cubit.state.revealedKey, isNull);
      expect(
        find.text('slk_shown_once'),
        findsNothing,
        reason: 'nothing in the app holds the value once the dialog is gone',
      );
      expect(
        find.text('ci'),
        findsOneWidget,
        reason: 'the key itself is in the list — as metadata',
      );
    });

    testWidgets('a revoked key stays listed, with its date', (tester) async {
      repository.keyList = [
        SecretKeyDto(
          id: 1,
          projectId: 1,
          label: 'legacy',
          createdAt: DateTime.utc(2025, 11, 20),
          revokedAt: DateTime.utc(2026, 1, 15),
        ),
      ];
      await pump(tester);

      expect(find.text('legacy'), findsOneWidget);
      expect(find.textContaining('Отозван'), findsOneWidget);
      expect(
        find.text('Отозвать'),
        findsNothing,
        reason: 'there is nothing left to revoke',
      );
    });

    testWidgets('a blocked project looks blocked', (tester) async {
      repository.one = ProjectDto(
        id: 1,
        groupId: 1,
        name: 'staging',
        retentionDays: 7,
        isBlocked: true,
        createdAt: DateTime.utc(2026, 2, 14),
      );
      await pump(tester);

      expect(find.text('Заблокирован'), findsOneWidget);
      expect(
        find.textContaining('заблокирован администратором'),
        findsOneWidget,
      );
    });

    testWidgets(
      'the block/unblock button is offered only to admin — the owner of '
      'the project itself would only get a 403',
      (tester) async {
        await pump(tester, isAdmin: false);
        expect(find.text('Заблокировать'), findsNothing);

        await pump(tester, isAdmin: true);
        expect(find.text('Заблокировать'), findsOneWidget);
      },
    );

    testWidgets('a refused revoke is explained in a banner, not silently '
        'dropped', (tester) async {
      roleAssignmentsFake.forScopeResult = [
        RoleAssignmentDto(
          id: 1,
          subjectType: 'user',
          subjectId: 9,
          subjectName: 'alice',
          role: 'owner',
          scopeType: 'project',
          scopeId: 1,
          createdAt: DateTime.utc(2026, 2, 14),
        ),
      ];
      roleAssignmentsFake.refuseWrites = const ApiFailure.forbidden(
        code: 'forbidden',
      );
      await pump(tester);
      expect(find.text('alice'), findsOneWidget);

      await tester.tap(find.text('Отозвать'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Отозвать').last);
      await tester.pumpAndSettle();

      expect(find.textContaining('Недостаточно прав'), findsOneWidget);
      expect(
        find.text('alice'),
        findsOneWidget,
        reason: 'the row a revoke was refused on is still there',
      );
    });
  });

  group("one group's detail", () {
    Future<void> pump(WidgetTester tester) async {
      useWideSurface(tester);
      final cubit = GroupDetailCubit(
        projects: ManageProjects(repository),
        roleAssignments: roleAssignments,
        teams: ManageTeams(repository),
        groupId: 1,
      )..load();
      addTearDown(cubit.close);
      await tester.pumpWidget(
        _host(
          BlocProvider.value(
            value: cubit,
            child: GroupDetailPage(
              groupName: 'Acme Corp',
              isAdmin: false,
              onBack: () {},
              onOpenProject: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'creating a team names the group it belongs to, and what to do next',
      (tester) async {
        await pump(tester);

        await tester.tap(find.text('Команда'));
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: find.byType(ContentDialog),
            matching: find.text('Acme Corp'),
          ),
          findsOneWidget,
          reason:
              'the group tag, so a reader with several groups open '
              'knows which one this team is going into',
        );
        expect(find.textContaining('добавьте участников'), findsOneWidget);
      },
    );
  });
}
