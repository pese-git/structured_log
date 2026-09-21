import 'dart:async';
import 'dart:io';

import 'package:cherrypick/cherrypick.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_server/src/auth/bootstrap_admin.dart';
import 'package:structured_log_server/src/auth/create_admin.dart';
import 'package:structured_log_server/src/auth/hashing.dart'
    show dummyPasswordHash;
import 'package:structured_log_server/src/config/config_resolver.dart';
import 'package:structured_log_server/src/config/server_config.dart';
import 'package:structured_log_server/src/http/process_resources.dart';
import 'package:structured_log_server/src/http/server.dart';
import 'package:structured_log_server/src/http/server_host.dart';
import 'package:structured_log_server/src/logging/setup.dart';
import 'package:structured_log_server/src/retention/purge_job.dart';
import 'package:structured_log_server/src/storage/database.dart';

const _version = '0.1.0-dev.0';

/// Stops a vanished console from killing the process.
///
/// Whoever reads this process's output can go away while it is still
/// running — `| head`, a supervisor that exited, a parent that stopped
/// reading the pipe. The next write then fails with a broken pipe, and
/// `dart:io` dispatches that failure through the **root** zone, so neither
/// a `try`/`catch` around the write nor a `runZonedGuarded` around `main`
/// ever sees it: it surfaces as an unhandled exception and exit code 255.
/// An otherwise clean shutdown reporting failure is worse than losing a
/// line of console output, and attaching a handler to the sink's `done`
/// future is what actually marks the error handled.
void _tolerateAClosedConsole() {
  stdout.done.catchError((Object _) {});
  stderr.done.catchError((Object _) {});
}

Future<void> main(List<String> arguments) async {
  _tolerateAClosedConsole();

  final String command;
  final List<String> configArgs;
  if (arguments.isNotEmpty && !arguments.first.startsWith('-')) {
    final candidate = arguments.first;
    if (candidate != commandServe && candidate != commandCreateAdmin) {
      stderr.writeln(
        'error: unknown command "$candidate" '
        '(expected "$commandServe" or "$commandCreateAdmin")',
      );
      exitCode = exitCodeConfigError;
      return;
    }
    command = candidate;
    configArgs = arguments.skip(1).toList();
  } else {
    command = commandServe;
    configArgs = arguments;
  }

  final result = ConfigResolver(
    serverConfigParams,
  ).parse(configArgs, Platform.environment, command: command);

  for (final warning in result.warnings) {
    stderr.writeln('warning: $warning');
  }

  switch (result.outcome) {
    case ConfigParseOutcome.help:
      stdout.writeln(
        'Usage: server.dart [$commandServe|$commandCreateAdmin] [options]\n',
      );
      stdout.writeln(result.helpText);
      return;
    case ConfigParseOutcome.version:
      stdout.writeln(_version);
      return;
    case ConfigParseOutcome.errors:
      for (final error in result.errors) {
        stderr.writeln('error: $error');
      }
      exitCode = exitCodeConfigError;
      return;
    case ConfigParseOutcome.printConfig:
      stdout.write(formatPrintConfig(serverConfigParams, result.values!));
      return;
    case ConfigParseOutcome.success:
      break;
  }

  final config = ServerConfig.fromResolved(result.values!);

  if (command == commandCreateAdmin) {
    await _runCreateAdmin(config);
  } else {
    await _runServe(config, result.values!);
  }
}

Future<void> _runCreateAdmin(ServerConfig config) async {
  final db = StructuredLogDatabase.open(config.dbPath);
  final outcome = await createAdmin(
    db,
    username: config.bootstrapAdminUsername,
    password: config.bootstrapAdminPassword,
  );
  await db.close();

  if (!outcome.success) {
    stderr.writeln('error: ${outcome.error}');
    exitCode = 1;
    return;
  }

  stdout.writeln('Created administrator "${config.bootstrapAdminUsername}".');
  final generated = outcome.generatedPassword;
  if (generated != null) {
    stderr.writeln(
      'warning: generated a temporary password: $generated — it must be '
      'changed at first login.',
    );
  }
}

Future<void> _runServe(
  ServerConfig config,
  Map<String, ResolvedValue> resolved,
) async {
  // Before anything else that can fail, so a problem opening the database
  // or bootstrapping the administrator is already reported through the
  // configured sinks rather than through whatever happens to be at hand
  // (`tasks.md` 33.2).
  final logging = configureServerLogging(config);
  final log = logging.logger;

  log.info(
    'server.starting',
    context: maskedConfigContext(serverConfigParams, resolved),
  );

  final db = StructuredLogDatabase.open(
    config.dbPath,
    readPool: config.dbReadPoolSize,
  );

  // Bootstrap runs before the port opens (design.md decision 49).
  await bootstrapAdmin(
    db,
    config,
    logWarning: (message) =>
        log.warning('bootstrap.warning', context: {'message': message}),
  );

  // The process's object graph lives in a scope opened through the helper, and
  // that scope *owns* what the process hands it — the database, the hash
  // workers, the logging (`ProcessResources`) — and closes them as it goes
  // down. Its layers (`http/server.dart`) are what make the order of that
  // right, so shutdown is one call rather than a list to keep in order.
  final graph = CherryPick.openScope(scopeName: serverScopeName);
  final handler = buildHandler(
    db,
    signingSecret: config.jwtSecret!,
    issuer: config.jwtIssuer,
    sseHeartbeatInterval: Duration(seconds: config.sseHeartbeatIntervalSeconds),
    config: config,
    logger: log,
    scope: graph,
    process: ProcessResources(logging: logging),
  );
  // Says whether the handler was built *into* that scope: a scope that was
  // opened and stayed empty looks the same from outside as one that was used.
  log.debug(
    'server.graph_opened',
    context: {'scope': serverScopeName, 'populated': serverGraphIsBuilt(graph)},
  );

  // The innermost layer: what only a running process has. Both are built by the
  // container and started here, in the order startup needs.
  final host = openServerHost(
    graph,
    config: config,
    handler: handler,
    logger: log,
  );

  // The periodic retention purge needs a long-running process to live in,
  // which is precisely why it belongs here and not in the library
  // (`tasks.md` 7.3). Started before the port opens so a backlog from a
  // previous run begins clearing immediately.
  host.resolve<PurgeScheduler>().start();

  // Before the first request: the dummy hash a login checks against for an
  // account that does not exist is made on first use, and that one login would
  // take twice as long as every other — a difference visible from outside.
  await dummyPasswordHash;

  final server = await host.resolve<ServerHost>().start();

  // Signal handlers before the readiness line, not after: that line is what
  // a supervisor waits for before considering the process up, and until the
  // handlers are installed a SIGTERM takes the default disposition and kills
  // it outright instead of shutting it down.
  final done = Completer<void>();
  final subscriptions = <StreamSubscription<ProcessSignal>>[
    ProcessSignal.sigint.watch().listen((_) => _shutdown(log, done)),
    if (!Platform.isWindows)
      ProcessSignal.sigterm.watch().listen((_) => _shutdown(log, done)),
  ];

  log.info(
    'server.started',
    context: {'host': server.address.host, 'port': server.port},
  );
  // Also on stdout, unconditionally: this line is the readiness signal a
  // supervisor waits for, and it must not disappear because the log level
  // was turned up or the log was pointed at a file.
  stdout.writeln('Listening on http://${server.address.host}:${server.port}');

  await done.future;
  for (final subscription in subscriptions) {
    await subscription.cancel();
  }
}

Future<void> _shutdown(BoundLogger log, Completer<void> done) async {
  if (done.isCompleted) return;
  log.info('server.stopping');
  stdout.writeln('Shutting down...');
  // Everything the process owns goes down here, innermost layer first: the
  // server stops accepting and its live subscriptions end, then the purge, then
  // the services, then the database and the hash workers, and last the logging,
  // so its queued writes land after everything that could still write a line
  // (`http/server.dart`, the layers).
  await CherryPick.closeScope(scopeName: serverScopeName);
  log.debug('server.graph_closed', context: {'scope': serverScopeName});
  done.complete();
}
