import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:structured_log_admin_client/features/resources/domain/resources_repository.dart';
import 'package:structured_log_admin_client/features/role_assignments/application/manage_role_assignments.dart';
import 'package:structured_log_admin_client/features/role_assignments/domain/role_assignments_repository.dart';
import 'package:structured_log_admin_client/features/users/application/manage_users.dart';
import 'package:structured_log_admin_client/features/users/domain/users_repository.dart';
import 'package:structured_log_admin_client/features/users/presentation/user_failure_text.dart';
import 'package:structured_log_admin_client/features/users/presentation/users_cubit.dart';
import 'package:structured_log_admin_client/shared/api/api_failure.dart';
import 'package:structured_log_admin_client/shared/api/dto/resource_dto.dart';
import 'package:structured_log_admin_client/shared/api/dto/user_dto.dart';

UserDto _user({
  int id = 1,
  String username = 'bob',
  String? displayName,
  bool mustChangePassword = true,
  bool isActive = true,
  DateTime? deletedAt,
  bool isPrimaryAdmin = false,
}) => UserDto(
  id: id,
  username: username,
  displayName: displayName,
  mustChangePassword: mustChangePassword,
  isActive: isActive,
  deletedAt: deletedAt,
  isPrimaryAdmin: isPrimaryAdmin,
  createdAt: DateTime.utc(2026, 9, 16),
);

class _FakeRepository implements UsersRepository {
  var page = <UserDto>[];
  String? nextCursor;

  ApiFailure? refuseEverything;
  ApiFailure? refuseWrites;

  final calls = <String>[];

  Either<ApiFailure, T> _answer<T>(T value, {bool write = false}) {
    final failure = refuseEverything ?? (write ? refuseWrites : null);
    return failure == null ? right(value) : left(failure);
  }

  @override
  Future<Either<ApiFailure, UserPageDto>> firstPage({int? limit}) async {
    calls.add('firstPage');
    return _answer(UserPageDto(items: page, nextCursor: nextCursor));
  }

  @override
  Future<Either<ApiFailure, UserPageDto>> nextPage({
    required String cursor,
    int? limit,
  }) async {
    calls.add('nextPage:$cursor');
    return _answer(UserPageDto(items: page, nextCursor: null));
  }

  @override
  Future<Either<ApiFailure, UserDto>> createUser({
    required String username,
    required String password,
    String? displayName,
  }) async {
    calls.add('createUser:$username');
    final created = _user(id: 99, username: username, displayName: displayName);
    return _answer(created, write: true);
  }

  @override
  Future<Either<ApiFailure, UserDto>> updateUser({
    required int userId,
    required String? displayName,
    String? password,
  }) async {
    calls.add('updateUser:$userId:$displayName:${password != null}');
    return _answer(
      _user(
        id: userId,
        displayName: displayName,
        mustChangePassword: password != null,
      ),
      write: true,
    );
  }

  @override
  Future<Either<ApiFailure, UserDto>> blockUser(int userId) async {
    calls.add('blockUser:$userId');
    return _answer(_user(id: userId, isActive: false), write: true);
  }

  @override
  Future<Either<ApiFailure, UserDto>> unblockUser(int userId) async {
    calls.add('unblockUser:$userId');
    return _answer(_user(id: userId), write: true);
  }

  @override
  Future<Either<ApiFailure, Unit>> deleteUser(int userId) async {
    calls.add('deleteUser:$userId');
    return _answer(unit, write: true);
  }
}

class _FakeRoleAssignments implements RoleAssignmentsRepository {
  var forUserResult = <RoleAssignmentDto>[];
  ApiFailure? refuseWrites;
  final calls = <String>[];

  Either<ApiFailure, T> _answer<T>(T value, {bool write = false}) {
    return write && refuseWrites != null ? left(refuseWrites!) : right(value);
  }

  @override
  Future<Either<ApiFailure, List<RoleAssignmentDto>>> forUser(
    int userId,
  ) async {
    calls.add('forUser:$userId');
    return right(forUserResult);
  }

  @override
  Future<Either<ApiFailure, RoleAssignmentDto>> grant({
    required int subjectId,
    required String role,
    required String scopeType,
    int? scopeId,
  }) async {
    calls.add('grant:$subjectId:$role:$scopeType:$scopeId');
    return _answer(
      RoleAssignmentDto(
        id: 1,
        subjectType: 'user',
        subjectId: subjectId,
        role: role,
        scopeType: scopeType,
        scopeId: scopeId,
        createdAt: DateTime.utc(2026, 9, 16),
      ),
      write: true,
    );
  }

  @override
  Future<Either<ApiFailure, Unit>> revoke(int assignmentId) async {
    calls.add('revoke:$assignmentId');
    return _answer(unit, write: true);
  }

  @override
  Never noSuchMethod(Invocation invocation) => throw UnimplementedError(
    '${invocation.memberName} is not used by users_test.dart',
  );
}

/// Only [groups]/[searchProjects] matter here — the role-grant picker's
/// data source — everything else in [ResourcesRepository] is unreachable
/// from this suite, which never opens the Groups/Projects screens.
class _FakeResources implements ResourcesRepository {
  var groupResults = <GroupDto>[];
  var projectResults = <ProjectDto>[];

  @override
  Future<Either<ApiFailure, List<GroupDto>>> groups({String? name}) async =>
      right(groupResults);

  @override
  Future<Either<ApiFailure, List<ProjectDto>>> searchProjects({
    String? name,
  }) async => right(projectResults);

  @override
  Never noSuchMethod(Invocation invocation) => throw UnimplementedError(
    '${invocation.memberName} is not used by users_test.dart',
  );
}

void main() {
  late _FakeRepository repository;
  late _FakeResources resources;
  late _FakeRoleAssignments roleAssignments;
  late UsersCubit cubit;

  setUp(() {
    repository = _FakeRepository();
    resources = _FakeResources();
    roleAssignments = _FakeRoleAssignments();
    cubit = UsersCubit(
      ManageUsers(repository),
      resources,
      ManageRoleAssignments(roleAssignments),
    );
  });
  tearDown(() => cubit.close());

  group('load', () {
    test('reads the first page', () async {
      repository.page = [_user(id: 2), _user(id: 1)];
      repository.nextCursor = '1';

      await cubit.load();

      expect(cubit.state.users, hasLength(2));
      expect(cubit.state.cursor, '1');
      expect(cubit.state.hasMore, isTrue);
      expect(cubit.state.loading, isFalse);
    });

    test('an empty list is said differently from a failed one', () async {
      await cubit.load();
      expect(cubit.state.isEmpty, isTrue);

      repository.refuseEverything = const ApiFailure.forbidden(
        code: 'forbidden',
      );
      await cubit.load();
      expect(cubit.state.isEmpty, isFalse);
      expect(cubit.state.failure, isNotNull);
    });
  });

  group('loadMore', () {
    test('appends the next page and keeps what was already shown', () async {
      repository.page = [_user(id: 2)];
      repository.nextCursor = '2';
      await cubit.load();

      repository.page = [_user(id: 1)];
      await cubit.loadMore();

      expect(cubit.state.users.map((u) => u.id), [2, 1]);
      expect(cubit.state.cursor, isNull);
      expect(repository.calls, ['firstPage', 'nextPage:2']);
    });

    test('does nothing without a cursor', () async {
      await cubit.load();
      await cubit.loadMore();
      expect(repository.calls, ['firstPage']);
    });
  });

  group('create', () {
    test('a created account is prepended, not reloaded', () async {
      repository.page = [_user(id: 1)];
      await cubit.load();

      await cubit.create(username: 'newbie', password: 'temp-123');

      expect(cubit.state.users.map((u) => u.id), [99, 1]);
      expect(cubit.state.created, isTrue);
      expect(repository.calls, ['firstPage', 'createUser:newbie']);
    });

    test('a refused create keeps the dialog open with a reason', () async {
      repository.refuseWrites = const ApiFailure.conflict(
        code: 'username_taken',
      );

      await cubit.create(username: 'taken', password: 'temp-123');

      expect(cubit.state.created, isFalse);
      expect(cubit.state.createFailure, isNotNull);
      expect(cubit.state.users, isEmpty);
    });
  });

  group('update', () {
    test('replaces the row in place, not the whole list', () async {
      repository.page = [
        _user(id: 1, username: 'a'),
        _user(id: 2, username: 'b'),
      ];
      await cubit.load();

      await cubit.update(userId: 2, displayName: 'Bob Diaz');

      expect(cubit.state.users[0].id, 1);
      expect(cubit.state.users[1].displayName, 'Bob Diaz');
    });

    test('setting a password marks the account temporary', () async {
      repository.page = [_user(id: 1, mustChangePassword: false)];
      await cubit.load();

      await cubit.update(userId: 1, displayName: null, password: 'new-pw');

      expect(cubit.state.users.single.mustChangePassword, isTrue);
    });
  });

  group('setBlocked', () {
    test('blocking and unblocking both replace the row', () async {
      repository.page = [_user(id: 1)];
      await cubit.load();

      await cubit.setBlocked(1, true);
      expect(cubit.state.users.single.isActive, isFalse);

      await cubit.setBlocked(1, false);
      expect(cubit.state.users.single.isActive, isTrue);
      expect(repository.calls, ['firstPage', 'blockUser:1', 'unblockUser:1']);
    });

    test('a refused unblock is explained as a deleted account', () async {
      repository.refuseWrites = const ApiFailure.conflict(
        code: 'deleted_account',
      );

      await cubit.setBlocked(1, false);

      expect(
        describeUserFailure(cubit.state.actionFailure!),
        contains('удалена'),
      );
    });
  });

  group('delete', () {
    test('removes the row from the list on success', () async {
      repository.page = [_user(id: 1), _user(id: 2)];
      await cubit.load();

      await cubit.delete(1);

      expect(cubit.state.users.map((u) => u.id), [2]);
    });

    test('a sole-group-owner refusal leaves the row in place', () async {
      repository.page = [_user(id: 1)];
      await cubit.load();
      repository.refuseWrites = const ApiFailure.conflict(
        code: 'sole_group_owner',
        details: {
          'blocking_groups': [
            {'id': 3, 'name': 'checkout-team'},
          ],
        },
      );

      await cubit.delete(1);

      expect(cubit.state.users, hasLength(1));
      expect(blockingGroupNames(cubit.state.actionFailure!), ['checkout-team']);
    });

    test('cannot_delete_primary_admin is explained specifically', () async {
      repository.refuseWrites = const ApiFailure.forbidden(
        code: 'cannot_delete_primary_admin',
      );

      await cubit.delete(1);

      expect(
        describeUserFailure(cubit.state.actionFailure!),
        contains('Основного администратора'),
      );
    });
  });

  group('loadRoleAssignments', () {
    test('populates the subject\'s grants', () async {
      roleAssignments.forUserResult = [
        RoleAssignmentDto(
          id: 1,
          subjectType: 'user',
          subjectId: 1,
          role: 'owner',
          scopeType: 'group',
          scopeId: 3,
          scopeName: 'payments',
          createdAt: DateTime.utc(2026, 9, 16),
        ),
      ];

      await cubit.loadRoleAssignments(1);

      expect(cubit.state.roleAssignments, hasLength(1));
      expect(cubit.state.roleAssignments.single.scopeName, 'payments');
    });
  });

  group('grantRole', () {
    test(
      'a successful grant reloads the grant list, not a one-shot flag',
      () async {
        roleAssignments.forUserResult = [
          RoleAssignmentDto(
            id: 1,
            subjectType: 'user',
            subjectId: 1,
            role: 'owner',
            scopeType: 'group',
            scopeId: 3,
            createdAt: DateTime.utc(2026, 9, 16),
          ),
        ];

        await cubit.grantRole(
          userId: 1,
          role: 'owner',
          scopeType: 'group',
          scopeId: 3,
        );

        expect(cubit.state.roleAssignments, hasLength(1));
        expect(
          roleAssignments.calls,
          containsAllInOrder(['grant:1:owner:group:3', 'forUser:1']),
        );
      },
    );

    test('a global grant carries no scope_id', () async {
      await cubit.grantRole(userId: 1, role: 'admin', scopeType: 'global');
      expect(roleAssignments.calls, contains('grant:1:admin:global:null'));
    });

    test('a refusal leaves the grant list untouched', () async {
      roleAssignments.refuseWrites = const ApiFailure.forbidden(
        code: 'forbidden',
      );

      await cubit.grantRole(userId: 1, role: 'admin', scopeType: 'global');

      expect(cubit.state.actionFailure, isNotNull);
      expect(cubit.state.roleAssignments, isEmpty);
    });

    test(
      'clearActionFailure also drops the previous subject\'s grants',
      () async {
        roleAssignments.forUserResult = [
          RoleAssignmentDto(
            id: 1,
            subjectType: 'user',
            subjectId: 1,
            role: 'user',
            scopeType: 'global',
            createdAt: DateTime.utc(2026, 9, 16),
          ),
        ];
        await cubit.loadRoleAssignments(1);
        expect(cubit.state.roleAssignments, isNotEmpty);

        cubit.clearActionFailure();

        expect(cubit.state.roleAssignments, isEmpty);
      },
    );
  });

  group('revokeRole', () {
    test('a successful revoke reloads the grant list', () async {
      await cubit.revokeRole(1, 5);

      expect(
        roleAssignments.calls,
        containsAllInOrder(['revoke:1', 'forUser:5']),
      );
    });
  });
}
