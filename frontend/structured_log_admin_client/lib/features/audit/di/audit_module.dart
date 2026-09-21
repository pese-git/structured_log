import 'package:cherrypick/cherrypick.dart';
import 'package:cherrypick_annotations/cherrypick_annotations.dart';

import '../../../shared/api/api_client.dart';
import '../application/query_audit_log.dart';
import '../domain/audit_repository.dart';
import '../infrastructure/audit_repository_impl.dart';
import '../presentation/audit_cubit.dart';

part 'audit_module.module.cherrypick.g.dart';

/// The audit log, in its own subscope (design.md decision 35).
///
/// Opened by the shell only for a reader whose token carries the global admin
/// role — but that is an offer, not a gate: the authority is the server's 403,
/// and this scope resolving for someone else would still get them nothing.
@module()
abstract class AuditModule extends Module {
  @singleton()
  @provide()
  AuditRepository auditRepository(ApiClient api) => AuditRepositoryImpl(api);

  @provide()
  QueryAuditLog queryAuditLog(AuditRepository repository) =>
      QueryAuditLog(repository);

  // Not a singleton: a cubit belongs to the screen that opened it and is
  // closed with it, so a second visit must get a fresh one rather than a
  // closed one — the same rule as `LogFeedBloc` next door.
  @provide()
  AuditCubit auditCubit(QueryAuditLog query) => AuditCubit(query);
}

const auditScopeName = 'audit';

Scope openAuditScope(Scope parent) =>
    parent.openSubScope(auditScopeName)..installModules([$AuditModule()]);

/// Disposes what audit's scope created and forgets it, so the next
/// [openAuditScope] starts from nothing rather than on top of the last one.
Future<void> closeAuditScope(Scope parent) =>
    parent.closeSubScope(auditScopeName);
