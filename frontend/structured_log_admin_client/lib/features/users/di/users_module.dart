import 'package:cherrypick/cherrypick.dart';

import '../../../shared/api/api_client.dart';
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

    bind<ManageUsers>().toProvide(
      () => ManageUsers(currentScope.resolve<UsersRepository>()),
    );

    // Not a singleton: the cubit belongs to the screen that opened it and is
    // closed with it (`AuditModule`, same rule).
    bind<UsersCubit>().toProvide(
      () => UsersCubit(currentScope.resolve<ManageUsers>()),
    );
  }
}

Scope openUsersScope(Scope parent) =>
    parent.openSubScope('users')..installModules([UsersModule()]);
