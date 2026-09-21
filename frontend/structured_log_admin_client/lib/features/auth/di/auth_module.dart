import 'package:cherrypick/cherrypick.dart';
import 'package:cherrypick_annotations/cherrypick_annotations.dart';
import 'package:structured_log/structured_log.dart';

import '../../../shared/api/api_client.dart';
import '../../../shared/auth/token_storage.dart';
import '../application/change_password.dart';
import '../application/delete_account.dart';
import '../application/restore_session.dart';
import '../application/sign_in.dart';
import '../application/sign_out.dart';
import '../domain/auth_repository.dart';
import '../infrastructure/auth_repository_impl.dart';

part 'auth_module.module.cherrypick.g.dart';

/// The auth feature's own bindings.
///
/// A feature module rather than more entries in `AppModule` (design.md
/// decision 35): what a feature needs is declared with the feature, and
/// installing it into a subscope means it can be composed and dropped without
/// touching the application's shared graph.
///
/// It resolves `ApiClient` and `TokenStorage` from the parent scope — a
/// subscope falls back to its parents, so shared singletons stay shared.
@module()
abstract class AuthModule extends Module {
  @singleton()
  @provide()
  AuthRepository authRepository(
    ApiClient api,
    TokenStorage storage,
    BoundLogger logger,
  ) => AuthRepositoryImpl(api: api.auth, storage: storage, logger: logger);

  // Use cases are cheap and stateless, so they are provided rather than kept
  // as singletons — a new one per screen costs nothing and keeps no state
  // that could outlive it.
  @provide()
  SignIn signIn(AuthRepository repository) => SignIn(repository);

  @provide()
  SignOut signOut(AuthRepository repository) => SignOut(repository);

  @provide()
  RestoreSession restoreSession(AuthRepository repository) =>
      RestoreSession(repository);

  @provide()
  ChangePassword changePassword(AuthRepository repository) =>
      ChangePassword(repository);

  @provide()
  CurrentUsername currentUsername(AuthRepository repository) =>
      CurrentUsername(repository);

  @provide()
  IsGlobalAdmin isGlobalAdmin(AuthRepository repository) =>
      IsGlobalAdmin(repository);

  // Resolves `ApiClient` directly, same as `authRepository` above —
  // its failure shape does not fit `AuthRepository` (see the class doc).
  @provide()
  DeleteAccount deleteAccount(ApiClient api, BoundLogger logger) =>
      DeleteAccount(api, logger);
}

const authScopeName = 'auth';

/// Opens the `auth` scope, or joins it if it is already open.
///
/// Two things use this scope at once — `AuthGate` and the `HomeShell` it hosts —
/// and both ask for it by name. `openSubScope` hands the second the first's
/// scope, and installing the module into it again put the same bindings on the
/// scope once per sign-in. The module is installed only when nothing in the
/// scope answers yet.
Scope openAuthScope(Scope parent) {
  final scope = parent.openSubScope(authScopeName);
  if (scope.tryResolve<AuthRepository>() == null) {
    scope.installModules([$AuthModule()]);
  }
  return scope;
}

/// Disposes what auth's scope created and forgets it, so the next
/// [openAuthScope] starts from nothing rather than on top of the last one.
Future<void> closeAuthScope(Scope parent) =>
    parent.closeSubScope(authScopeName);
