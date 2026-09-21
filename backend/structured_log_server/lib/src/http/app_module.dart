import 'package:cherrypick/cherrypick.dart';

import '../auth/token_settings.dart';
import '../live/log_broadcast.dart';
import '../logging/setup.dart';
import 'http_settings.dart';
import 'routes/audit_log_route.dart' show AuditRetention;

/// What the server is *given* rather than builds: its settings and the broadcast
/// the caller may need to close (the database is bound one layer below, where
/// what owns it decides whether the scope closes it).
///
/// The outermost layer, so what a process hands over to be closed last —
/// the logging, whose queued writes must land after everything that could still
/// write a line — lives here.
///
/// Handwritten, unlike the feature modules beside it, because it carries values
/// in its constructor and a generated module (`$Name`) is built with none. It is
/// the only module that does — everything else is derived from what is bound
/// here.
class AppModule extends Module {
  final TokenSettings tokens;
  final HttpSettings http;
  final AuditRetention auditRetention;
  final LogBroadcast broadcast;

  /// Only a process has any (`ProcessResources`). Bound through a provider, not
  /// as an instance: a scope closes what its bindings *create*, and an instance
  /// handed in is not one.
  final ServerLogging? logging;

  AppModule({
    required this.tokens,
    required this.http,
    required this.auditRetention,
    required this.broadcast,
    this.logging,
  });

  @override
  void builder(Scope currentScope) {
    bind<TokenSettings>().toInstance(tokens);
    bind<HttpSettings>().toInstance(http);
    bind<AuditRetention>().toInstance(auditRetention);
    bind<LogBroadcast>().toInstance(broadcast);
    final owned = logging;
    if (owned != null) bind<ServerLogging>().toProvide(() => owned).singleton();
  }
}
