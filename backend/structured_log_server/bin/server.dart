import 'dart:async';
import 'dart:io';

import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:structured_log_server/src/auth/bootstrap_admin.dart';
import 'package:structured_log_server/src/auth/create_admin.dart';
import 'package:structured_log_server/src/config/config_resolver.dart';
import 'package:structured_log_server/src/config/server_config.dart';
import 'package:structured_log_server/src/http/server.dart';
import 'package:structured_log_server/src/live/log_broadcast.dart';
import 'package:structured_log_server/src/storage/database.dart';

const _version = '0.1.0-dev.0';

Future<void> main(List<String> arguments) async {
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
    await _runServe(config);
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

Future<void> _runServe(ServerConfig config) async {
  final db = StructuredLogDatabase.open(config.dbPath);

  // Bootstrap runs before the port opens (design.md decision 49).
  await bootstrapAdmin(
    db,
    config,
    logWarning: (message) => stderr.writeln('warning: $message'),
  );

  // Owned here rather than by buildHandler so shutdown can close it and
  // every open `GET /v1/logs/stream` subscription ends with the process
  // instead of hanging on a stream that will never produce again.
  final logBroadcast = LogBroadcast();
  final handler = buildHandler(
    db,
    signingSecret: config.jwtSigningSecret!,
    issuer: config.jwtIssuer,
    broadcast: logBroadcast,
    sseHeartbeatInterval: Duration(seconds: config.sseHeartbeatIntervalSeconds),
  );

  final server =
      await shelf_io.serve(handler, config.httpHost, config.httpPort);
  stdout.writeln('Listening on http://${server.address.host}:${server.port}');

  final done = Completer<void>();
  final subscriptions = <StreamSubscription<ProcessSignal>>[
    ProcessSignal.sigint
        .watch()
        .listen((_) => _shutdown(server, db, logBroadcast, done)),
    if (!Platform.isWindows)
      ProcessSignal.sigterm
          .watch()
          .listen((_) => _shutdown(server, db, logBroadcast, done)),
  ];

  await done.future;
  for (final subscription in subscriptions) {
    await subscription.cancel();
  }
}

Future<void> _shutdown(
  HttpServer server,
  StructuredLogDatabase db,
  LogBroadcast broadcast,
  Completer<void> done,
) async {
  if (done.isCompleted) return;
  stdout.writeln('Shutting down...');
  // Close the broadcast before the server: an open subscription that is
  // still being fed while the socket goes away would keep the process
  // alive on a stream nobody can read.
  await broadcast.close();
  await server.close(force: false);
  await db.close();
  done.complete();
}
