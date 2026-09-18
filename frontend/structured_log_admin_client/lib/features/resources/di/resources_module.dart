import 'package:cherrypick/cherrypick.dart';

import '../../../shared/api/api_client.dart';
import '../../role_assignments/application/manage_role_assignments.dart';
import '../../role_assignments/domain/role_assignments_repository.dart';
import '../../role_assignments/infrastructure/role_assignments_repository_impl.dart';
import '../application/manage_resources.dart';
import '../domain/resources_repository.dart';
import '../infrastructure/resources_repository_impl.dart';

/// Groups, projects and secret keys, in their own subscope
/// (design.md decision 35).
class ResourcesModule extends Module {
  @override
  void builder(Scope currentScope) {
    bind<ResourcesRepository>()
        .toProvide(
          () => ResourcesRepositoryImpl(currentScope.resolve<ApiClient>()),
        )
        .singleton();

    // Rebound here, same reasoning as `ResourcesRepository` being rebound
    // into `UsersModule` — for the group/project «Доступ» section
    // (`RoleAssignmentsRepository.forScope`/`searchUsers`).
    bind<RoleAssignmentsRepository>()
        .toProvide(
          () =>
              RoleAssignmentsRepositoryImpl(currentScope.resolve<ApiClient>()),
        )
        .singleton();

    bind<ManageGroups>().toProvide(
      () => ManageGroups(currentScope.resolve<ResourcesRepository>()),
    );
    bind<ManageProjects>().toProvide(
      () => ManageProjects(currentScope.resolve<ResourcesRepository>()),
    );
    bind<ManageTeams>().toProvide(
      () => ManageTeams(currentScope.resolve<ResourcesRepository>()),
    );
    bind<ManageSecretKeys>().toProvide(
      () => ManageSecretKeys(currentScope.resolve<ResourcesRepository>()),
    );
    bind<ManageRoleAssignments>().toProvide(
      () => ManageRoleAssignments(
        currentScope.resolve<RoleAssignmentsRepository>(),
      ),
    );
  }
}

Scope openResourcesScope(Scope parent) =>
    parent.openSubScope('resources')..installModules([ResourcesModule()]);
