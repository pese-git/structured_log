import 'package:cherrypick/cherrypick.dart';
import 'package:cherrypick_annotations/cherrypick_annotations.dart';

import '../audit/audit_writer.dart';
import '../rbac/authorizer.dart';
import '../storage/database.dart';
import 'claims.dart';
import 'identity_provider.dart';
import 'local_identity_provider.dart';
import 'token_service.dart';
import 'token_settings.dart';

part 'auth_module.module.cherrypick.g.dart';

@module()
abstract class AuthModule extends Module {
  @singleton()
  @provide()
  ClaimsResolver claimsResolver(
    StructuredLogDatabase db,
    Authorizer authorizer,
  ) => ClaimsResolver(db, authorizer);

  @singleton()
  @provide()
  TokenService tokenService(
    StructuredLogDatabase db,
    ClaimsResolver claims,
    AuditWriter audit,
    TokenSettings tokens,
  ) => TokenService(
    db,
    claims,
    audit,
    signingSecret: tokens.signingSecret,
    issuer: tokens.issuer,
  );

  // Behind the interface: the local provider is the only one today, and what
  // consumers depend on is that a bearer token can be turned into an identity.
  @singleton()
  @provide()
  IdentityProvider identityProvider(
    StructuredLogDatabase db,
    TokenSettings tokens,
  ) => LocalIdentityProvider(
    db,
    signingSecret: tokens.signingSecret,
    issuer: tokens.issuer,
  );
}
