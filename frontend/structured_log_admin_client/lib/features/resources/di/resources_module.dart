import 'package:cherrypick/cherrypick.dart';

import '../../../shared/api/api_client.dart';
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

    bind<ManageGroups>().toProvide(
      () => ManageGroups(currentScope.resolve<ResourcesRepository>()),
    );
    bind<ManageProjects>().toProvide(
      () => ManageProjects(currentScope.resolve<ResourcesRepository>()),
    );
    bind<ManageSecretKeys>().toProvide(
      () => ManageSecretKeys(currentScope.resolve<ResourcesRepository>()),
    );
  }
}

Scope openResourcesScope(Scope parent) =>
    parent.openSubScope('resources')..installModules([ResourcesModule()]);
