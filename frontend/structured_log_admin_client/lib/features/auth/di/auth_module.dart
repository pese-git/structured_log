import 'package:cherrypick/cherrypick.dart';
import 'package:structured_log/structured_log.dart';

import '../../../shared/api/api_client.dart';
import '../../../shared/auth/token_storage.dart';
import '../application/restore_session.dart';
import '../application/sign_in.dart';
import '../application/sign_out.dart';
import '../domain/auth_repository.dart';
import '../infrastructure/auth_repository_impl.dart';

/// The auth feature's own bindings.
///
/// A feature module rather than more entries in `AppModule` (design.md
/// decision 35): what a feature needs is declared with the feature, and
/// installing it into a subscope means it can be composed and dropped without
/// touching the application's shared graph.
///
/// It resolves `ApiClient` and `TokenStorage` from the parent scope — a
/// subscope falls back to its parents, so shared singletons stay shared.
class AuthModule extends Module {
  @override
  void builder(Scope currentScope) {
    bind<AuthRepository>()
        .toProvide(
          () => AuthRepositoryImpl(
            api: currentScope.resolve<ApiClient>().auth,
            storage: currentScope.resolve<TokenStorage>(),
            logger: currentScope.resolve<BoundLogger>(),
          ),
        )
        .singleton();

    // Use cases are cheap and stateless, so they are provided rather than kept
    // as singletons — a new one per screen costs nothing and keeps no state
    // that could outlive it.
    bind<SignIn>().toProvide(
      () => SignIn(currentScope.resolve<AuthRepository>()),
    );
    bind<SignOut>().toProvide(
      () => SignOut(currentScope.resolve<AuthRepository>()),
    );
    bind<RestoreSession>().toProvide(
      () => RestoreSession(currentScope.resolve<AuthRepository>()),
    );
  }
}

/// Opens (or reuses) the auth subscope under [parent].
Scope openAuthScope(Scope parent) =>
    parent.openSubScope('auth')..installModules([AuthModule()]);
