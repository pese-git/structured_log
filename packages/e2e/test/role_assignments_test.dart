import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log_admin_client/features/resources/domain/resources_repository.dart';
import 'package:structured_log_admin_client/features/resources/infrastructure/resources_repository_impl.dart';
import 'package:structured_log_admin_client/features/role_assignments/application/manage_role_assignments.dart';
import 'package:structured_log_admin_client/features/role_assignments/infrastructure/role_assignments_repository_impl.dart';
import 'package:structured_log_admin_client/features/users/application/manage_users.dart';
import 'package:structured_log_admin_client/features/users/infrastructure/users_repository_impl.dart';
import 'package:structured_log_admin_client/shared/api/api_client.dart';
import 'package:structured_log_admin_client/shared/api/api_failure.dart';
import 'package:structured_log_admin_client/shared/api/dto/auth_dto.dart';
import 'package:structured_log_admin_client/shared/auth/token_pair.dart';
import 'package:structured_log_admin_client/shared/auth/token_storage.dart';
import 'package:structured_log_admin_client/shared/config/app_config.dart';

import 'harness.dart';

/// The access-management flow added alongside role assignments (`design.md`,
/// уточнение 17.09.2026): an admin grants a group's `owner` role to a
/// regular user, that user's session gains exactly what an `owner` should
/// have and nothing more, and revoking the grant takes it away again.
///
/// A manual pass through this same sequence — grant, sign in as the new
/// owner, create a project in the granted group, confirm the owner reads its
/// own access list but cannot write or read another scope's, revoke, confirm
/// the project is refused afterward — was run by hand against a live server
/// before this file existed. This is that pass, made repeatable.
void main() {
  late ServerProcess server;

  late ApiClient adminApi;
  late InMemoryTokenStorage adminStorage;
  late ResourcesRepository adminResources;
  late ManageUsers adminUsers;
  late ManageRoleAssignments adminRoleAssignments;

  late ApiClient ownerApi;
  late InMemoryTokenStorage ownerStorage;
  late ResourcesRepository ownerResources;
  late ManageRoleAssignments ownerRoleAssignments;

  const adminNewPassword = 'chosen-by-the-administrator';
  const ownerTemporaryPassword = 'issued-by-the-administrator';
  const ownerChosenPassword = 'chosen-by-the-owner';

  /// Wires one identity's worth of client stack against [server] — its own
  /// token storage, so two identities never share a session.
  ({
    ApiClient api,
    InMemoryTokenStorage storage,
    ResourcesRepository resources,
    ManageRoleAssignments roleAssignments,
  })
  clientFor() {
    final storage = InMemoryTokenStorage();
    final api = ApiClient(
      config: AppConfig(baseUrl: server.baseUrl),
      storage: storage,
    );
    return (
      api: api,
      storage: storage,
      resources: ResourcesRepositoryImpl(api),
      roleAssignments: ManageRoleAssignments(
        RoleAssignmentsRepositoryImpl(api),
      ),
    );
  }

  Future<void> signIn(
    ApiClient api,
    InMemoryTokenStorage storage, {
    required String username,
    required String password,
  }) async {
    final tokens = await api.auth.signIn('password', username, password);
    await storage.write(
      TokenPair(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
      ),
    );
  }

  setUpAll(() async {
    server = await ServerProcess.start();

    final admin = clientFor();
    adminApi = admin.api;
    adminStorage = admin.storage;
    adminResources = admin.resources;
    adminUsers = ManageUsers(UsersRepositoryImpl(adminApi));
    adminRoleAssignments = admin.roleAssignments;

    await signIn(
      adminApi,
      adminStorage,
      username: 'admin',
      password: server.bootstrapPassword,
    );
    await adminApi.auth.changePassword(
      ChangePasswordRequestDto(
        currentPassword: server.bootstrapPassword,
        newPassword: adminNewPassword,
      ),
    );

    final owner = clientFor();
    ownerApi = owner.api;
    ownerStorage = owner.storage;
    ownerResources = owner.resources;
    ownerRoleAssignments = owner.roleAssignments;
  });

  tearDownAll(() async {
    await server.stop();
  });

  late int ownedGroupId;
  late int otherGroupId;
  late int ownerUserId;
  late int grantId;

  test('an admin grants a group to a regular user, who signs in and changes '
      'the temporary password', () async {
    final ownedGroup = (await adminResources.createGroup('payments')).getOrElse(
      (failure) => fail('creating the owned group failed: $failure'),
    );
    ownedGroupId = ownedGroup.id;

    final otherGroup = (await adminResources.createGroup('unrelated'))
        .getOrElse(
          (failure) => fail('creating the other group failed: $failure'),
        );
    otherGroupId = otherGroup.id;

    final user = (await adminUsers.create(
      username: 'operator',
      password: ownerTemporaryPassword,
    )).getOrElse((failure) => fail('creating the user failed: $failure'));
    ownerUserId = user.id;

    final grant = (await adminRoleAssignments.grant(
      subjectType: 'user',
      subjectId: ownerUserId,
      role: 'owner',
      scopeType: 'group',
      scopeId: ownedGroupId,
    )).getOrElse((failure) => fail('granting the role failed: $failure'));
    grantId = grant.id;
    expect(
      grant.scopeName,
      isNull,
      reason:
          'a POST only ever echoes back what the caller sent — the '
          'name comes from a GET, which resolves it server-side',
    );

    final resolved =
        (await adminRoleAssignments.forScope(
          scopeType: 'group',
          scopeId: ownedGroupId,
        )).getOrElse(
          (failure) => fail('reading the fresh grant back failed: $failure'),
        );
    final row = resolved.singleWhere((a) => a.id == grantId);
    expect(row.scopeName, 'payments');
    expect(row.subjectName, 'operator');

    await signIn(
      ownerApi,
      ownerStorage,
      username: 'operator',
      password: ownerTemporaryPassword,
    );
    final refused = await ownerResources.groups();
    expect(
      refused.isLeft(),
      isTrue,
      reason:
          'the temporary password gate applies to a granted account '
          'the same as a freshly bootstrapped one',
    );

    await ownerApi.auth.changePassword(
      ChangePasswordRequestDto(
        currentPassword: ownerTemporaryPassword,
        newPassword: ownerChosenPassword,
      ),
    );
  });

  test('the owner reads their own group\'s access list, but neither another '
      'scope\'s nor a bare subject filter', () async {
    final own = (await ownerRoleAssignments.forScope(
      scopeType: 'group',
      scopeId: ownedGroupId,
    )).getOrElse((failure) => fail('reading the owned scope failed: $failure'));
    expect(own.map((a) => a.id), contains(grantId));

    final other = await ownerRoleAssignments.forScope(
      scopeType: 'group',
      scopeId: otherGroupId,
    );
    expect(
      other.isLeft(),
      isTrue,
      reason: 'owning one group does not open every group\'s access list',
    );
    other.match(
      (failure) => expect(failure, isA<ForbiddenFailure>()),
      (_) => fail('the scope check should have stopped this'),
    );

    final bySubject = await ownerRoleAssignments.forUser(ownerUserId);
    expect(
      bySubject.isLeft(),
      isTrue,
      reason:
          'a subject-only filter stays admin-only even for the '
          'subject\'s own grants — only a scope-shaped query is opened to '
          'an owner',
    );
    bySubject.match(
      (failure) => expect(failure, isA<ForbiddenFailure>()),
      (_) => fail('the subject-only check should have stopped this'),
    );
  });

  test('the owner creates a project in the granted group, and can delegate '
      'roles within it — but not on another group\'s', () async {
    final project =
        (await ownerResources.createProject(
          groupId: ownedGroupId,
          name: 'checkout',
          retentionDays: 30,
        )).getOrElse(
          (failure) =>
              fail('the owner\'s own group refused a project: $failure'),
        );
    expect(project.name, 'checkout');

    // Full 4.3 (`design.md` "Delivery Phases", Этап 4): an owner may grant
    // and revoke `owner`/`user` roles inside their own group — read access
    // to the scope's list (previous test) was never the same right as
    // this, but this stage grants both.
    final teammate = (await adminUsers.create(
      username: 'teammate',
      password: 'issued-by-the-administrator-too',
    )).getOrElse((failure) => fail('creating the teammate failed: $failure'));

    final delegated =
        (await ownerRoleAssignments.grant(
          subjectType: 'user',
          subjectId: teammate.id,
          role: 'user',
          scopeType: 'group',
          scopeId: ownedGroupId,
        )).getOrElse(
          (failure) => fail(
            'the owner\'s own group refused a delegated grant: $failure',
          ),
        );

    final revokedByOwner = await ownerRoleAssignments.revoke(delegated.id);
    expect(
      revokedByOwner.isRight(),
      isTrue,
      reason: 'an owner may also revoke what they delegated in their own group',
    );

    final deniedGrant = await ownerRoleAssignments.grant(
      subjectType: 'user',
      subjectId: teammate.id,
      role: 'user',
      scopeType: 'group',
      scopeId: otherGroupId,
    );
    expect(
      deniedGrant.isLeft(),
      isTrue,
      reason:
          'the rule is scoped to the group the owner actually owns, not '
          'every group',
    );
    deniedGrant.match(
      (failure) => expect(failure, isA<ForbiddenFailure>()),
      (_) => fail('the scope check should have stopped this'),
    );
  });

  test('once the admin revokes the grant, the former owner loses both group '
      'access and the ability to create another project there', () async {
    // The operator holds the group's only owner grant, and a group is never
    // left without one by an ordinary action — not even the administrator's.
    final refused = await adminRoleAssignments.revoke(grantId);
    refused.match(
      (failure) => expect(
        failure,
        isA<ConflictFailure>().having(
          (f) => f.code,
          'code',
          'sole_group_owner',
        ),
      ),
      (_) => fail('revoking the last owner grant should have been refused'),
    );

    final successor = (await adminUsers.create(
      username: 'successor',
      password: ownerTemporaryPassword,
    )).getOrElse((failure) => fail('creating the successor failed: $failure'));
    (await adminRoleAssignments.grant(
      subjectType: 'user',
      subjectId: successor.id,
      role: 'owner',
      scopeType: 'group',
      scopeId: ownedGroupId,
    )).getOrElse((failure) => fail('granting the successor failed: $failure'));

    final revoked = await adminRoleAssignments.revoke(grantId);
    expect(revoked.isRight(), isTrue);

    final remaining = (await adminRoleAssignments.forScope(
      scopeType: 'group',
      scopeId: ownedGroupId,
    )).getOrElse((failure) => fail('reading the scope back failed: $failure'));
    expect(remaining.map((a) => a.subjectName), [
      'successor',
    ], reason: 'the operator\'s grant is gone, the successor\'s is not');

    final deniedProject = await ownerResources.createProject(
      groupId: ownedGroupId,
      name: 'refunds',
      retentionDays: 30,
    );
    expect(
      deniedProject.isLeft(),
      isTrue,
      reason:
          'the revoke takes effect on the operator\'s very next '
          'request, not just on a future sign-in',
    );
    deniedProject.match(
      (failure) => expect(failure, isA<ForbiddenFailure>()),
      (_) => fail('the revoke should have stopped this'),
    );
  });
}
