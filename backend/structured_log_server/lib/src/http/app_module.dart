import 'package:cherrypick/cherrypick.dart';

import '../auth/token_settings.dart';
import '../live/log_broadcast.dart';
import '../storage/database.dart';
import 'http_settings.dart';
import 'routes/audit_log_route.dart' show AuditRetention;

/// What the server is *given* rather than builds: the database, its settings,
/// and the broadcast the caller may need to close.
///
/// Handwritten, unlike the feature modules beside it, because it carries values
/// in its constructor and a generated module (`$Name`) is built with none. It is
/// the only module that does — everything else is derived from what is bound
/// here.
class AppModule extends Module {
  final StructuredLogDatabase db;
  final TokenSettings tokens;
  final HttpSettings http;
  final AuditRetention auditRetention;
  final LogBroadcast broadcast;

  AppModule({
    required this.db,
    required this.tokens,
    required this.http,
    required this.auditRetention,
    required this.broadcast,
  });

  @override
  void builder(Scope currentScope) {
    bind<StructuredLogDatabase>().toInstance(db);
    bind<TokenSettings>().toInstance(tokens);
    bind<HttpSettings>().toInstance(http);
    bind<AuditRetention>().toInstance(auditRetention);
    bind<LogBroadcast>().toInstance(broadcast);
  }
}
