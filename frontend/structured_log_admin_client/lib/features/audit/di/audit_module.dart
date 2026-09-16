import 'package:cherrypick/cherrypick.dart';

import '../../../shared/api/api_client.dart';
import '../application/query_audit_log.dart';
import '../domain/audit_repository.dart';
import '../infrastructure/audit_repository_impl.dart';

/// The audit log, in its own subscope (design.md decision 35).
///
/// Opened by the shell only for a reader whose token carries the global admin
/// role — but that is an offer, not a gate: the authority is the server's 403,
/// and this scope resolving for someone else would still get them nothing.
class AuditModule extends Module {
  @override
  void builder(Scope currentScope) {
    bind<AuditRepository>()
        .toProvide(() => AuditRepositoryImpl(currentScope.resolve<ApiClient>()))
        .singleton();

    bind<QueryAuditLog>().toProvide(
      () => QueryAuditLog(currentScope.resolve<AuditRepository>()),
    );
  }
}

Scope openAuditScope(Scope parent) =>
    parent.openSubScope('audit')..installModules([AuditModule()]);
