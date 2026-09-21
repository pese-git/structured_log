import 'package:cherrypick/cherrypick.dart';
import 'package:shelf/shelf.dart';
import 'package:structured_log/structured_log.dart';

import '../audit/audit_writer.dart';
import '../config/server_config.dart';
import '../live/log_broadcast.dart';
import '../retention/purge_job.dart';
import '../storage/database.dart';
import 'server_host.dart';

/// What only a running process has: the periodic retention purge and the
/// listening server. The innermost layer, so both go down before anything they
/// use.
///
/// Handwritten, like `AppModule`: it carries the configuration and the handler
/// it was given. Nothing here starts on its own — a provider builds the object,
/// and `bin/server.dart` starts it, in the order startup needs.
class HostModule extends Module {
  final ServerConfig config;
  final Handler handler;
  final BoundLogger? logger;

  HostModule({required this.config, required this.handler, this.logger});

  @override
  void builder(Scope currentScope) {
    bind<PurgeScheduler>()
        .toProvide(
          () => PurgeScheduler(
            currentScope.resolve<StructuredLogDatabase>(),
            interval: Duration(seconds: config.retentionPurgeIntervalSeconds),
            logger: logger,
            audit: currentScope.resolve<AuditWriter>(),
            auditRetentionDays: config.auditRetentionDays,
            authEventRetentionDays: config.authEventRetentionDays,
            auditChunkSize: config.auditPurgeBatchSize,
          ),
        )
        .singleton();

    bind<ServerHost>()
        .toProvide(
          () => ServerHost(
            handler,
            currentScope.resolve<LogBroadcast>(),
            host: config.httpHost,
            port: config.httpPort,
          ),
        )
        .singleton();
  }
}
