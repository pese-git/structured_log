import 'package:cherrypick/cherrypick.dart';

import '../../../shared/api/api_client.dart';
import '../../resources/domain/resources_repository.dart';
import '../../resources/infrastructure/resources_repository_impl.dart';
import '../../role_assignments/application/manage_role_assignments.dart';
import '../../role_assignments/domain/role_assignments_repository.dart';
import '../../role_assignments/infrastructure/role_assignments_repository_impl.dart';
import '../application/manage_users.dart';
import '../domain/users_repository.dart';
import '../infrastructure/users_repository_impl.dart';
import '../presentation/users_cubit.dart';

/// User management, in its own subscope (design.md decision 35). Opened by
/// the shell only for a reader whose token carries the global admin role —
/// an offer, not a gate: the authority is the server's 403 on every one of
/// these endpoints (`AuditModule`, same reasoning).
class UsersModule extends Module {
  @override
  void builder(Scope currentScope) {
    bind<UsersRepository>()
        .toProvide(() => UsersRepositoryImpl(currentScope.resolve<ApiClient>()))
        .singleton();

    // For the role-grant form's group/project search — the same repository
    // `ResourcesModule` binds for the Groups/Projects screens, rebound here
    // because this subscope is opened independently of that one and cannot
    // resolve into it (`AuditModule`, same shape of problem).
    bind<ResourcesRepository>()
        .toProvide(
          () => ResourcesRepositoryImpl(currentScope.resolve<ApiClient>()),
        )
        .singleton();

    // Same rebinding, same reason, for the role-grant list/grant/revoke —
    // `ResourcesModule` binds the same class for the group/project «Доступ»
    // section.
    bind<RoleAssignmentsRepository>()
        .toProvide(
          () =>
              RoleAssignmentsRepositoryImpl(currentScope.resolve<ApiClient>()),
        )
        .singleton();

    bind<ManageUsers>().toProvide(
      () => ManageUsers(currentScope.resolve<UsersRepository>()),
    );
    bind<ManageRoleAssignments>().toProvide(
      () => ManageRoleAssignments(
        currentScope.resolve<RoleAssignmentsRepository>(),
      ),
    );

    // Not a singleton: the cubit belongs to the screen that opened it and is
    // closed with it (`AuditModule`, same rule).
    bind<UsersCubit>().toProvide(
      () => UsersCubit(
        currentScope.resolve<ManageUsers>(),
        currentScope.resolve<ResourcesRepository>(),
        currentScope.resolve<ManageRoleAssignments>(),
      ),
    );
  }
}

Scope openUsersScope(Scope parent) =>
    parent.openSubScope('users')..installModules([UsersModule()]);
