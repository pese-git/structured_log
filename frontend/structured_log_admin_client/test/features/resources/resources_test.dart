import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:structured_log_admin_client/features/resources/application/manage_resources.dart';
import 'package:structured_log_admin_client/features/resources/domain/resources_repository.dart';
import 'package:structured_log_admin_client/features/resources/presentation/group_detail_cubit.dart';
import 'package:structured_log_admin_client/features/resources/presentation/groups_cubit.dart';
import 'package:structured_log_admin_client/features/resources/presentation/project_detail_cubit.dart';
import 'package:structured_log_admin_client/features/resources/presentation/resource_failure_text.dart';
import 'package:structured_log_admin_client/features/role_assignments/application/manage_role_assignments.dart';
import 'package:structured_log_admin_client/features/role_assignments/domain/role_assignments_repository.dart';
import 'package:structured_log_admin_client/shared/api/api_failure.dart';
import 'package:structured_log_admin_client/shared/api/dto/resource_dto.dart';
import 'package:structured_log_admin_client/shared/api/dto/user_dto.dart';

GroupDto _group(int id, String name) =>
    GroupDto(id: id, name: name, createdAt: DateTime.utc(2026, 2, 14));

ProjectDto _project({
  int id = 1,
  String name = 'checkout',
  int? maxEntries = 1000,
  int? maxBytes,
  int? entryCount,
  int? totalBytes,
  bool isBlocked = false,
}) => ProjectDto(
  id: id,
  groupId: 1,
  name: name,
  retentionDays: 30,
  maxEntries: maxEntries,
  maxBytes: maxBytes,
  isBlocked: isBlocked,
  createdAt: DateTime.utc(2026, 2, 14),
  entryCount: entryCount,
  totalBytes: totalBytes,
);

SecretKeyDto _key({int id = 1, String label = 'ci', DateTime? revokedAt}) =>
    SecretKeyDto(
      id: id,
      projectId: 1,
      label: label,
      createdAt: DateTime.utc(2026, 2, 14),
      revokedAt: revokedAt,
    );

class _FakeRepository implements ResourcesRepository {
  var groupList = <GroupDto>[];
  var projectList = <ProjectDto>[];
  var keyList = <SecretKeyDto>[];
  ProjectDto one = _project();

  ApiFailure? refuseEverything;
  ApiFailure? refuseWrites;

  final calls = <String>[];
  ({int retentionDays, int? maxEntries, int? maxBytes})? lastQuota;

  Either<ApiFailure, T> _answer<T>(T value, {bool write = false}) {
    final failure = refuseEverything ?? (write ? refuseWrites : null);
    return failure == null ? right(value) : left(failure);
  }

  @override
  Future<Either<ApiFailure, List<GroupDto>>> groups({String? name}) async {
    calls.add('groups');
    return _answer(groupList);
  }

  @override
  Future<Either<ApiFailure, GroupDto>> createGroup(String name) async {
    calls.add('createGroup:$name');
    final created = _group(groupList.length + 1, name);
    if (refuseEverything == null && refuseWrites == null) {
      groupList = [...groupList, created];
    }
    return _answer(created, write: true);
  }

  @override
  Future<Either<ApiFailure, List<ProjectDto>>> projectsOf(int groupId) async {
    calls.add('projectsOf:$groupId');
    return _answer(projectList);
  }

  @override
  Future<Either<ApiFailure, List<ProjectDto>>> searchProjects({
    String? name,
  }) async {
    calls.add('searchProjects');
    return _answer(projectList);
  }

  @override
  Future<Either<ApiFailure, ProjectDto>> project(int projectId) async {
    calls.add('project:$projectId');
    return _answer(one);
  }

  @override
  Future<Either<ApiFailure, ProjectDto>> createProject({
    required int groupId,
    required String name,
    required int retentionDays,
    int? maxEntries,
    int? maxBytes,
  }) async {
    calls.add('createProject:$name');
    lastQuota = (
      retentionDays: retentionDays,
      maxEntries: maxEntries,
      maxBytes: maxBytes,
    );
    final created = _project(id: projectList.length + 1, name: name);
    if (refuseEverything == null && refuseWrites == null) {
      projectList = [...projectList, created];
    }
    return _answer(created, write: true);
  }

  @override
  Future<Either<ApiFailure, ProjectDto>> updateQuota({
    required int projectId,
    required int retentionDays,
    required int? maxEntries,
    required int? maxBytes,
  }) async {
    calls.add('updateQuota:$projectId');
    lastQuota = (
      retentionDays: retentionDays,
      maxEntries: maxEntries,
      maxBytes: maxBytes,
    );
    // The server answers with the saved project — and without usage counters,
    // which only `GET /v1/projects/{id}` computes.
    return _answer(
      _project(id: projectId, maxEntries: maxEntries, maxBytes: maxBytes),
      write: true,
    );
  }

  @override
  Future<Either<ApiFailure, List<SecretKeyDto>>> secretKeys(
    int projectId,
  ) async {
    calls.add('secretKeys:$projectId');
    return _answer(keyList);
  }

  @override
  Future<Either<ApiFailure, SecretKeyDto>> createSecretKey({
    required int projectId,
    required String label,
  }) async {
    calls.add('createSecretKey:$label');
    final created = SecretKeyDto(
      id: keyList.length + 1,
      projectId: projectId,
      label: label,
      createdAt: DateTime.utc(2026, 2, 14),
      secret: 'slk_generated_once',
    );
    if (refuseEverything == null && refuseWrites == null) {
      keyList = [...keyList, _key(id: created.id, label: label)];
    }
    return _answer(created, write: true);
  }

  @override
  Future<Either<ApiFailure, Unit>> revokeSecretKey({
    required int projectId,
    required int keyId,
  }) async {
    calls.add('revoke:$keyId');
    if (refuseEverything == null && refuseWrites == null) {
      keyList = [
        for (final key in keyList)
          if (key.id == keyId)
            _key(
              id: key.id,
              label: key.label,
              revokedAt: DateTime.utc(2026, 3, 1),
            )
          else
            key,
      ];
    }
    return _answer(unit, write: true);
  }

  @override
  Future<Either<ApiFailure, ProjectDto>> blockProject(int projectId) async {
    calls.add('blockProject:$projectId');
    return _answer(one.copyWith(isBlocked: true), write: true);
  }

  @override
  Future<Either<ApiFailure, ProjectDto>> unblockProject(int projectId) async {
    calls.add('unblockProject:$projectId');
    return _answer(one.copyWith(isBlocked: false), write: true);
  }

  var teamList = <TeamDto>[];
  final teamMemberLists = <int, List<TeamMemberDto>>{};

  @override
  Future<Either<ApiFailure, List<TeamDto>>> teamsOf(int groupId) async {
    calls.add('teamsOf:$groupId');
    return _answer(teamList);
  }

  @override
  Future<Either<ApiFailure, TeamDto>> createTeam({
    required int groupId,
    required String name,
  }) async {
    calls.add('createTeam:$name');
    final created = TeamDto(
      id: teamList.length + 1,
      groupId: groupId,
      name: name,
      createdAt: DateTime.utc(2026, 2, 14),
    );
    if (refuseEverything == null && refuseWrites == null) {
      teamList = [...teamList, created];
    }
    return _answer(created, write: true);
  }

  @override
  Future<Either<ApiFailure, List<TeamMemberDto>>> teamMembers(
    int teamId,
  ) async {
    calls.add('teamMembers:$teamId');
    return _answer(teamMemberLists[teamId] ?? const []);
  }

  @override
  Future<Either<ApiFailure, Unit>> addTeamMember({
    required int teamId,
    required int userId,
  }) async {
    calls.add('addTeamMember:$teamId:$userId');
    if (refuseEverything == null && refuseWrites == null) {
      final current = teamMemberLists[teamId] ?? const [];
      if (!current.any((m) => m.userId == userId)) {
        teamMemberLists[teamId] = [
          ...current,
          TeamMemberDto(userId: userId, username: 'user$userId'),
        ];
      }
    }
    return _answer(unit, write: true);
  }

  @override
  Future<Either<ApiFailure, Unit>> removeTeamMember({
    required int teamId,
    required int userId,
  }) async {
    calls.add('removeTeamMember:$teamId:$userId');
    if (refuseEverything == null && refuseWrites == null) {
      teamMemberLists[teamId] = [
        for (final m in teamMemberLists[teamId] ?? const [])
          if (m.userId != userId) m,
      ];
    }
    return _answer(unit, write: true);
  }
}

class _FakeRoleAssignments implements RoleAssignmentsRepository {
  var forScopeResult = <RoleAssignmentDto>[];
  var searchResult = <UserDto>[];
  ApiFailure? refuseWrites;
  final calls = <String>[];

  @override
  Future<Either<ApiFailure, List<RoleAssignmentDto>>> forScope({
    required String scopeType,
    required int scopeId,
  }) async {
    calls.add('forScope:$scopeType:$scopeId');
    return right(forScopeResult);
  }

  @override
  Future<Either<ApiFailure, RoleAssignmentDto>> grant({
    required String subjectType,
    required int subjectId,
    required String role,
    required String scopeType,
    int? scopeId,
  }) async {
    calls.add('grant:$subjectType:$subjectId:$role:$scopeType:$scopeId');
    if (refuseWrites != null) return left(refuseWrites!);
    return right(
      RoleAssignmentDto(
        id: 1,
        subjectType: subjectType,
        subjectId: subjectId,
        role: role,
        scopeType: scopeType,
        scopeId: scopeId,
        createdAt: DateTime.utc(2026, 2, 14),
      ),
    );
  }

  @override
  Future<Either<ApiFailure, Unit>> revoke(int assignmentId) async {
    calls.add('revoke:$assignmentId');
    if (refuseWrites != null) return left(refuseWrites!);
    return right(unit);
  }

  @override
  Future<Either<ApiFailure, List<UserDto>>> searchUsers(String username) async {
    calls.add('searchUsers:$username');
    return right(searchResult);
  }

  @override
  Never noSuchMethod(Invocation invocation) => throw UnimplementedError(
    '${invocation.memberName} is not used by resources_test.dart',
  );
}

void main() {
  late _FakeRepository repository;
  late _FakeRoleAssignments roleAssignments;

  setUp(() {
    repository = _FakeRepository();
    roleAssignments = _FakeRoleAssignments();
  });

  group('groups', () {
    test('a created group shows up because the list is re-read', () async {
      final cubit = GroupsCubit(ManageGroups(repository));
      addTearDown(cubit.close);
      await cubit.load();

      await cubit.create('payments');

      expect(cubit.state.groups.map((g) => g.name), ['payments']);
      expect(
        repository.calls,
        ['groups', 'createGroup:payments', 'groups'],
        reason:
            'the server decides what this caller may see; a group they '
            'created is not automatically one they are shown',
      );
    });

    test('a refused create keeps the dialog open with a reason', () async {
      repository.refuseWrites = const ApiFailure.forbidden(code: 'forbidden');
      final cubit = GroupsCubit(ManageGroups(repository));
      addTearDown(cubit.close);
      await cubit.load();

      await cubit.create('payments');

      expect(cubit.state.created, isFalse);
      expect(cubit.state.createFailure, isA<ForbiddenFailure>());
      expect(
        cubit.state.failure,
        isNull,
        reason: "a dialog's refusal does not deface the page behind it",
      );
    });

    test('an empty list is said differently from a failed one', () async {
      final cubit = GroupsCubit(ManageGroups(repository));
      addTearDown(cubit.close);

      await cubit.load();
      expect(cubit.state.isEmpty, isTrue);

      repository.refuseEverything = const ApiFailure.network();
      await cubit.load();
      expect(cubit.state.isEmpty, isFalse);
      expect(cubit.state.failure, isNotNull);
    });
  });

  group('projects in a group', () {
    test('an unlimited quota is sent as absent, not as zero', () async {
      final cubit = GroupDetailCubit(
        projects: ManageProjects(repository),
        roleAssignments: ManageRoleAssignments(roleAssignments),
        teams: ManageTeams(repository),
        groupId: 1,
      );
      addTearDown(cubit.close);
      await cubit.load();

      await cubit.create(name: 'checkout', retentionDays: 30);

      expect(repository.lastQuota?.maxEntries, isNull);
      expect(repository.lastQuota?.maxBytes, isNull);
      expect(cubit.state.projects.map((p) => p.name), ['checkout']);
    });
  });

  group('access to a group', () {
    test('the grant list loads alongside the projects', () async {
      roleAssignments.forScopeResult = [
        RoleAssignmentDto(
          id: 1,
          subjectType: 'user',
          subjectId: 9,
          subjectName: 'alice',
          role: 'owner',
          scopeType: 'group',
          scopeId: 1,
          createdAt: DateTime.utc(2026, 2, 14),
        ),
      ];
      final cubit = GroupDetailCubit(
        projects: ManageProjects(repository),
        roleAssignments: ManageRoleAssignments(roleAssignments),
        teams: ManageTeams(repository),
        groupId: 1,
      );
      addTearDown(cubit.close);

      await cubit.load();

      expect(cubit.state.roleAssignments.single.subjectName, 'alice');
      expect(roleAssignments.calls, contains('forScope:group:1'));
    });

    test('granting reloads the list, scoped to this group', () async {
      final cubit = GroupDetailCubit(
        projects: ManageProjects(repository),
        roleAssignments: ManageRoleAssignments(roleAssignments),
        teams: ManageTeams(repository),
        groupId: 1,
      );
      addTearDown(cubit.close);
      await cubit.load();

      await cubit.grantAccess(subjectType: 'user', subjectId: 9, role: 'owner');

      expect(
        roleAssignments.calls,
        containsAllInOrder(['grant:user:9:owner:group:1', 'forScope:group:1']),
      );
    });

    test('a refused grant is explained, not silently dropped', () async {
      roleAssignments.refuseWrites = const ApiFailure.forbidden(
        code: 'forbidden',
      );
      final cubit = GroupDetailCubit(
        projects: ManageProjects(repository),
        roleAssignments: ManageRoleAssignments(roleAssignments),
        teams: ManageTeams(repository),
        groupId: 1,
      );
      addTearDown(cubit.close);
      await cubit.load();

      await cubit.grantAccess(subjectType: 'user', subjectId: 9, role: 'owner');

      expect(cubit.state.accessFailure, isNotNull);
    });

    test('revoking reloads the list too', () async {
      final cubit = GroupDetailCubit(
        projects: ManageProjects(repository),
        roleAssignments: ManageRoleAssignments(roleAssignments),
        teams: ManageTeams(repository),
        groupId: 1,
      );
      addTearDown(cubit.close);
      await cubit.load();

      await cubit.revokeAccess(1);

      expect(
        roleAssignments.calls,
        containsAllInOrder(['revoke:1', 'forScope:group:1']),
      );
    });

    test('a refused revoke is explained too — an owner sees the server\'s '
        'reason, not a silent no-op', () async {
      roleAssignments.forScopeResult = [
        RoleAssignmentDto(
          id: 1,
          subjectType: 'user',
          subjectId: 9,
          subjectName: 'alice',
          role: 'owner',
          scopeType: 'group',
          scopeId: 1,
          createdAt: DateTime.utc(2026, 2, 14),
        ),
      ];
      roleAssignments.refuseWrites = const ApiFailure.forbidden(
        code: 'forbidden',
      );
      final cubit = GroupDetailCubit(
        projects: ManageProjects(repository),
        roleAssignments: ManageRoleAssignments(roleAssignments),
        teams: ManageTeams(repository),
        groupId: 1,
      );
      addTearDown(cubit.close);
      await cubit.load();

      await cubit.revokeAccess(1);

      expect(cubit.state.accessFailure, isNotNull);
      expect(
        cubit.state.roleAssignments,
        hasLength(1),
        reason: 'the row a revoke was refused on is still there',
      );
    });
  });

  group('teams in a group', () {
    test('the team list loads alongside the projects', () async {
      repository.teamList = [
        TeamDto(
          id: 1,
          groupId: 1,
          name: 'on-call',
          createdAt: DateTime.utc(2026, 2, 14),
        ),
      ];
      final cubit = GroupDetailCubit(
        projects: ManageProjects(repository),
        roleAssignments: ManageRoleAssignments(roleAssignments),
        teams: ManageTeams(repository),
        groupId: 1,
      );
      addTearDown(cubit.close);

      await cubit.load();

      expect(cubit.state.teams.single.name, 'on-call');
    });

    test('creating a team reloads the list', () async {
      final cubit = GroupDetailCubit(
        projects: ManageProjects(repository),
        roleAssignments: ManageRoleAssignments(roleAssignments),
        teams: ManageTeams(repository),
        groupId: 1,
      );
      addTearDown(cubit.close);
      await cubit.load();

      await cubit.createTeam('on-call');

      expect(cubit.state.teams.map((t) => t.name), ['on-call']);
      expect(cubit.state.teamCreated, isTrue);
      expect(
        repository.calls,
        containsAllInOrder(['createTeam:on-call', 'teamsOf:1']),
      );
    });

    test(
      'a refused team creation is explained, not silently dropped',
      () async {
        repository.refuseWrites = const ApiFailure.forbidden(code: 'forbidden');
        final cubit = GroupDetailCubit(
          projects: ManageProjects(repository),
          roleAssignments: ManageRoleAssignments(roleAssignments),
          teams: ManageTeams(repository),
          groupId: 1,
        );
        addTearDown(cubit.close);
        await cubit.load();

        await cubit.createTeam('on-call');

        expect(cubit.state.teamCreated, isFalse);
        expect(cubit.state.createTeamFailure, isA<ForbiddenFailure>());
      },
    );

    test('opening the composition dialog loads its current members', () async {
      final cubit = GroupDetailCubit(
        projects: ManageProjects(repository),
        roleAssignments: ManageRoleAssignments(roleAssignments),
        teams: ManageTeams(repository),
        groupId: 1,
      );
      addTearDown(cubit.close);
      await cubit.load();
      repository.teamMemberLists[7] = [
        const TeamMemberDto(userId: 9, username: 'alice'),
      ];

      await cubit.openTeamMembers(7);

      expect(cubit.state.managingTeamId, 7);
      expect(cubit.state.teamMembers.single.username, 'alice');
      expect(cubit.state.loadingTeamMembers, isFalse);
    });

    test('adding a member reloads the composition for the open team', () async {
      final cubit = GroupDetailCubit(
        projects: ManageProjects(repository),
        roleAssignments: ManageRoleAssignments(roleAssignments),
        teams: ManageTeams(repository),
        groupId: 1,
      );
      addTearDown(cubit.close);
      await cubit.load();
      await cubit.openTeamMembers(7);

      await cubit.addTeamMember(9);

      expect(cubit.state.teamMembers.single.userId, 9);
      expect(
        repository.calls,
        containsAllInOrder(['addTeamMember:7:9', 'teamMembers:7']),
      );
    });

    test('removing a member reloads the composition too', () async {
      repository.teamMemberLists[7] = [
        const TeamMemberDto(userId: 9, username: 'alice'),
      ];
      final cubit = GroupDetailCubit(
        projects: ManageProjects(repository),
        roleAssignments: ManageRoleAssignments(roleAssignments),
        teams: ManageTeams(repository),
        groupId: 1,
      );
      addTearDown(cubit.close);
      await cubit.load();
      await cubit.openTeamMembers(7);

      await cubit.removeTeamMember(9);

      expect(cubit.state.teamMembers, isEmpty);
      expect(
        repository.calls,
        containsAllInOrder(['removeTeamMember:7:9', 'teamMembers:7']),
      );
    });

    test(
      'a refused add is explained and does not touch the shown list',
      () async {
        final cubit = GroupDetailCubit(
          projects: ManageProjects(repository),
          roleAssignments: ManageRoleAssignments(roleAssignments),
          teams: ManageTeams(repository),
          groupId: 1,
        );
        addTearDown(cubit.close);
        await cubit.load();
        await cubit.openTeamMembers(7);
        repository.refuseWrites = const ApiFailure.forbidden(code: 'forbidden');

        await cubit.addTeamMember(9);

        expect(cubit.state.teamMembersFailure, isNotNull);
        expect(cubit.state.teamMembers, isEmpty);
      },
    );

    test('closing the dialog clears which team is being managed', () async {
      final cubit = GroupDetailCubit(
        projects: ManageProjects(repository),
        roleAssignments: ManageRoleAssignments(roleAssignments),
        teams: ManageTeams(repository),
        groupId: 1,
      );
      addTearDown(cubit.close);
      await cubit.load();
      await cubit.openTeamMembers(7);

      cubit.closeTeamMembers();

      expect(cubit.state.managingTeamId, isNull);
    });
  });

  group('one project', () {
    test('the quota and the keys are loaded together', () async {
      repository.one = _project(entryCount: 842, totalBytes: 1024);
      repository.keyList = [_key()];
      final cubit = ProjectDetailCubit(
        projects: ManageProjects(repository),
        keys: ManageSecretKeys(repository),
        roleAssignments: ManageRoleAssignments(roleAssignments),
        teams: ManageTeams(repository),
        projectId: 1,
      );
      addTearDown(cubit.close);

      await cubit.load();

      expect(cubit.state.project?.entryCount, 842);
      expect(cubit.state.keys, hasLength(1));
    });

    test('saving a quota keeps the usage counters it already had', () async {
      repository.one = _project(entryCount: 842, totalBytes: 4096);
      final cubit = ProjectDetailCubit(
        projects: ManageProjects(repository),
        keys: ManageSecretKeys(repository),
        roleAssignments: ManageRoleAssignments(roleAssignments),
        teams: ManageTeams(repository),
        projectId: 1,
      );
      addTearDown(cubit.close);
      await cubit.load();

      await cubit.updateQuota(
        retentionDays: 30,
        maxEntries: 5000,
        maxBytes: null,
      );

      expect(cubit.state.project?.maxEntries, 5000);
      expect(
        cubit.state.project?.entryCount,
        842,
        reason:
            'PATCH answers without counters; dropping them would blank the '
            'usage bars until the next full load',
      );
    });

    test('a created key is held once, then forgotten', () async {
      final cubit = ProjectDetailCubit(
        projects: ManageProjects(repository),
        keys: ManageSecretKeys(repository),
        roleAssignments: ManageRoleAssignments(roleAssignments),
        teams: ManageTeams(repository),
        projectId: 1,
      );
      addTearDown(cubit.close);
      await cubit.load();

      await cubit.createKey('ci');
      expect(cubit.state.revealedKey?.secret, 'slk_generated_once');
      expect(
        cubit.state.keys.single.secret,
        isNull,
        reason:
            'the listing is metadata only — the value lives in '
            'revealedKey and nowhere else',
      );

      cubit.dismissRevealedKey();
      expect(cubit.state.revealedKey, isNull);
    });

    test('a revoked key stays in the list, marked', () async {
      repository.keyList = [_key(label: 'ci')];
      final cubit = ProjectDetailCubit(
        projects: ManageProjects(repository),
        keys: ManageSecretKeys(repository),
        roleAssignments: ManageRoleAssignments(roleAssignments),
        teams: ManageTeams(repository),
        projectId: 1,
      );
      addTearDown(cubit.close);
      await cubit.load();

      await cubit.revokeKey(1);

      expect(cubit.state.keys, hasLength(1));
      expect(cubit.state.keys.single.revokedAt, isNotNull);
    });
  });

  group('access to a project', () {
    test('the grant list loads scoped to the project, not the group', () async {
      final cubit = ProjectDetailCubit(
        projects: ManageProjects(repository),
        keys: ManageSecretKeys(repository),
        roleAssignments: ManageRoleAssignments(roleAssignments),
        teams: ManageTeams(repository),
        projectId: 1,
      );
      addTearDown(cubit.close);

      await cubit.load();

      expect(roleAssignments.calls, contains('forScope:project:1'));
    });

    test('the user search picker degrades to empty on failure', () async {
      final cubit = ProjectDetailCubit(
        projects: ManageProjects(repository),
        keys: ManageSecretKeys(repository),
        roleAssignments: ManageRoleAssignments(roleAssignments),
        teams: ManageTeams(repository),
        projectId: 1,
      );
      addTearDown(cubit.close);

      final result = await cubit.searchUsers('ali');

      expect(result, isEmpty);
      expect(roleAssignments.calls, contains('searchUsers:ali'));
    });
  });

  group('what the screens say about a refusal', () {
    test('a 403 names the roles that would have been enough', () {
      expect(
        describeApiFailure(const ApiFailure.forbidden(code: 'forbidden')),
        contains('администратору'),
      );
    });

    test('a 409 is a name already taken', () {
      expect(
        describeApiFailure(const ApiFailure.conflict(code: 'conflict')),
        contains('уже занято'),
      );
    });
  });

  group('the numbers on screen', () {
    test('counts are grouped, and do not wrap mid-number', () {
      expect(formatCount(1000000), '1\u00A0000\u00A0000');
      expect(formatCount(842), '842');
    });

    test('bytes are stated in the unit the quota field uses', () {
      expect(formatBytes(5 * 1024 * 1024), '5\u00A0МБ');
      expect(formatBytes(2048), '2\u00A0КБ');
    });
  });
}
