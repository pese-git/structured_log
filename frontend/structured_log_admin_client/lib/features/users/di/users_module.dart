import 'package:cherrypick/cherrypick.dart';
import 'package:cherrypick_annotations/cherrypick_annotations.dart';

import '../../../shared/api/api_client.dart';
import '../../audit/application/query_audit_log.dart';
import '../../audit/domain/audit_repository.dart';
import '../../audit/infrastructure/audit_repository_impl.dart';
import '../../resources/domain/resources_repository.dart';
import '../../resources/infrastructure/resources_repository_impl.dart';
import '../../role_assignments/application/manage_role_assignments.dart';
import '../../role_assignments/domain/role_assignments_repository.dart';
import '../../role_assignments/infrastructure/role_assignments_repository_impl.dart';
import '../application/manage_users.dart';
import '../domain/users_repository.dart';
import '../infrastructure/users_repository_impl.dart';
import '../presentation/users_cubit.dart';

part 'users_module.module.cherrypick.g.dart';

/// User management, in its own subscope (design.md decision 35). Opened by
/// the shell only for a reader whose token carries the global admin role —
/// an offer, not a gate: the authority is the server's 403 on every one of
/// these endpoints (`AuditModule`, same reasoning).
@module()
abstract class UsersModule extends Module {
  @singleton()
  @provide()
  UsersRepository usersRepository(ApiClient api) => UsersRepositoryImpl(api);

  // For the role-grant form's group/project search — the same repository
  // `ResourcesModule` binds for the Groups/Projects screens, rebound here
  // because this subscope is opened independently of that one and cannot
  // resolve into it (`AuditModule`, same shape of problem).
  @singleton()
  @provide()
  ResourcesRepository resourcesRepository(ApiClient api) =>
      ResourcesRepositoryImpl(api);

  // Same rebinding, same reason, for the role-grant list/grant/revoke —
  // `ResourcesModule` binds the same class for the group/project «Доступ»
  // section.
  @singleton()
  @provide()
  RoleAssignmentsRepository roleAssignmentsRepository(ApiClient api) =>
      RoleAssignmentsRepositoryImpl(api);

  // Same rebinding again, for `UserDetailPage`'s "Последние события
  // аудита" card — `AuditModule` binds the same classes for the audit
  // screen itself.
  @singleton()
  @provide()
  AuditRepository auditRepository(ApiClient api) => AuditRepositoryImpl(api);

  @provide()
  ManageUsers manageUsers(UsersRepository repository) =>
      ManageUsers(repository);

  @provide()
  ManageRoleAssignments manageRoleAssignments(
    RoleAssignmentsRepository repository,
  ) => ManageRoleAssignments(repository);

  @provide()
  QueryAuditLog queryAuditLog(AuditRepository repository) =>
      QueryAuditLog(repository);

  // Not a singleton: the cubit belongs to the screen that opened it and is
  // closed with it (`AuditModule`, same rule).
  @provide()
  UsersCubit usersCubit(
    ManageUsers users,
    ResourcesRepository resources,
    ManageRoleAssignments roleAssignments,
    QueryAuditLog audit,
  ) => UsersCubit(users, resources, roleAssignments, audit);
}

const usersScopeName = 'users';

Scope openUsersScope(Scope parent) =>
    parent.openSubScope(usersScopeName)..installModules([$UsersModule()]);

/// Disposes what users's scope created and forgets it, so the next
/// [openUsersScope] starts from nothing rather than on top of the last one.
Future<void> closeUsersScope(Scope parent) =>
    parent.closeSubScope(usersScopeName);
