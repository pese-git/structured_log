import 'package:cherrypick/cherrypick.dart';
import 'package:cherrypick_annotations/cherrypick_annotations.dart';

import '../../../shared/api/api_client.dart';
import '../../role_assignments/application/manage_role_assignments.dart';
import '../../role_assignments/domain/role_assignments_repository.dart';
import '../../role_assignments/infrastructure/role_assignments_repository_impl.dart';
import '../application/manage_resources.dart';
import '../domain/resources_repository.dart';
import '../infrastructure/resources_repository_impl.dart';

part 'resources_module.module.cherrypick.g.dart';

/// Groups, projects and secret keys, in their own subscope
/// (design.md decision 35).
@module()
abstract class ResourcesModule extends Module {
  @singleton()
  @provide()
  ResourcesRepository resourcesRepository(ApiClient api) =>
      ResourcesRepositoryImpl(api);

  // Rebound here, same reasoning as `ResourcesRepository` being rebound
  // into `UsersModule` — for the group/project «Доступ» section
  // (`RoleAssignmentsRepository.forScope`/`searchUsers`).
  @singleton()
  @provide()
  RoleAssignmentsRepository roleAssignmentsRepository(ApiClient api) =>
      RoleAssignmentsRepositoryImpl(api);

  @provide()
  ManageGroups manageGroups(ResourcesRepository repository) =>
      ManageGroups(repository);

  @provide()
  ManageProjects manageProjects(ResourcesRepository repository) =>
      ManageProjects(repository);

  @provide()
  ManageTeams manageTeams(ResourcesRepository repository) =>
      ManageTeams(repository);

  @provide()
  ManageSecretKeys manageSecretKeys(ResourcesRepository repository) =>
      ManageSecretKeys(repository);

  @provide()
  ManageRoleAssignments manageRoleAssignments(
    RoleAssignmentsRepository repository,
  ) => ManageRoleAssignments(repository);
}

const resourcesScopeName = 'resources';

Scope openResourcesScope(Scope parent) =>
    parent.openSubScope(resourcesScopeName)
      ..installModules([$ResourcesModule()]);

/// Disposes what resources's scope created and forgets it, so the next
/// [openResourcesScope] starts from nothing rather than on top of the last one.
Future<void> closeResourcesScope(Scope parent) =>
    parent.closeSubScope(resourcesScopeName);
