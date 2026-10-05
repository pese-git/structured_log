import 'package:logging/logging.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_logging/structured_log_logging.dart';

void main() {
  StructlogConfiguration.configure(output: jsonLineOutput);

  // package:logging's own gate: records below it are never created, so they
  // never reach the bridge. The bridge leaves it to you.
  Logger.root.level = Level.ALL;
  final bridge = StructuredLogLoggingBridge()..attach();

  // What a library writing through package:logging does.
  final db = Logger('db');
  db.config('pool size 4');
  db.fine('query took 3 ms');
  try {
    throw StateError('connection closed');
  } catch (error, stackTrace) {
    db.severe('query failed', error, stackTrace);
  }

  // Your own entries go to the same outputs.
  getLogger('app').info('ready');

  bridge.detach();
}
