// Integration tests for structured_log.
//
// Unlike test/structlog_test.dart (which exercises each component in
// isolation, mostly through custom OutputFunction closures that capture
// entries in memory), these tests exercise the package as a whole system:
// real files on a real filesystem, multiple features combined the way a
// consumer actually would (correlation + bound context + processors +
// multi-sink routing + sync/async outputs together), and end-to-end
// behaviors (rotation content, console formatting) that only show up when
// the full pipeline runs.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:structured_log/structured_log.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir =
        Directory.systemTemp.createTempSync('structured_log_integration_');
  });

  tearDown(() {
    StructlogConfiguration.reset();
    tempDir.deleteSync(recursive: true);
  });

  test(
      'correlation, bound context, and processors round-trip through a real '
      'file on disk', () {
    final path = '${tempDir.path}/app.log';
    StructlogConfiguration.configure(
      processors: [dropNullValues],
      output: fileOutput(path),
    );

    final log = getLogger('checkout')
        .bind({'request_id': 'r-bound'}).withCorrelation(
            sessionId: 's-1', requestId: 'r-typed');

    log.info('purchase', context: {'amount': 42, 'discount': null});

    final entry =
        jsonDecode(File(path).readAsLinesSync().single) as Map<String, dynamic>;

    expect(entry['event'], 'purchase');
    expect(entry['logger'], 'checkout');
    // Typed correlation field wins over the same-named bound context key.
    expect(entry['request_id'], 'r-typed');
    expect(entry['session_id'], 's-1');
    expect(entry['amount'], 42);
    // dropNullValues removed the null field.
    expect(entry.containsKey('discount'), isFalse);
    expect(entry['level'], 'info');
    expect(entry.containsKey('timestamp'), isTrue);
  });

  test(
      'multi-sink routing delivers every entry to one file and only '
      'protocol-tagged entries to another, on real files, with runtime '
      'toggling', () {
    final allPath = '${tempDir.path}/all.log';
    final protocolPath = '${tempDir.path}/protocol.log';

    StructlogConfiguration.configure(sinks: [
      LogSink(name: 'all', output: fileOutput(allPath)),
      LogSink(
        name: 'protocol',
        output: fileOutput(protocolPath),
        categories: {'protocol'},
      ),
    ]);

    final log = getLogger();
    log.info('app_started');
    log.debug('raw_frame_1', context: {'category': 'protocol'});
    log.info('app_event');

    StructlogConfiguration.setSinkEnabled('protocol', enabled: false);
    log.debug('raw_frame_2', context: {'category': 'protocol'});

    final allEvents = File(allPath)
        .readAsLinesSync()
        .map((l) => jsonDecode(l)['event'])
        .toList();
    final protocolEvents = File(protocolPath)
        .readAsLinesSync()
        .map((l) => jsonDecode(l)['event'])
        .toList();

    expect(
        allEvents, ['app_started', 'raw_frame_1', 'app_event', 'raw_frame_2']);
    // raw_frame_2 was logged after the protocol sink was disabled.
    expect(protocolEvents, ['raw_frame_1']);
  });

  test(
      'trace-level protocol tracing stays out of the general sink by level '
      'alone, with no category tagging needed, and lands on a dedicated '
      'async trace sink', () async {
    final generalPath = '${tempDir.path}/general.log';
    final tracePath = '${tempDir.path}/trace.log';
    final traceOutput = AsyncFileOutput(tracePath);

    // The general sink uses the default minLevel (debug), so it never sees
    // trace-level entries -- no categories: filter required.
    StructlogConfiguration.configure(sinks: [
      LogSink(name: 'general', output: fileOutput(generalPath)),
      LogSink(name: 'trace', output: traceOutput, minLevel: LogLevel.trace),
    ]);

    final log = getLogger();
    log.info('request_started');
    log.trace('raw_frame', context: {'bytes': 128});
    log.info('request_completed');
    await traceOutput.flushed;

    final generalEvents =
        File(generalPath).readAsLinesSync().map((l) => jsonDecode(l)['event']);
    final traceEvents =
        File(tracePath).readAsLinesSync().map((l) => jsonDecode(l)['event']);

    expect(generalEvents, ['request_started', 'request_completed']);
    expect(traceEvents, ['request_started', 'raw_frame', 'request_completed']);
  });

  test(
      'a sync file sink and an async file sink both receive the same '
      'entries, in order, from one multi-sink configuration', () async {
    final syncPath = '${tempDir.path}/sync.log';
    final asyncPath = '${tempDir.path}/async.log';
    final asyncOutput = AsyncFileOutput(asyncPath);

    StructlogConfiguration.configure(sinks: [
      LogSink(name: 'sync', output: fileOutput(syncPath)),
      LogSink(name: 'async', output: asyncOutput),
    ]);

    final log = getLogger();
    for (var i = 0; i < 10; i++) {
      log.info('event', context: {'i': i});
    }
    await asyncOutput.flushed;

    final syncIndices =
        File(syncPath).readAsLinesSync().map((l) => jsonDecode(l)['i']);
    final asyncIndices =
        File(asyncPath).readAsLinesSync().map((l) => jsonDecode(l)['i']);

    expect(syncIndices, List.generate(10, (i) => i));
    expect(asyncIndices, List.generate(10, (i) => i));
  });

  test(
      'sync rotating file output preserves the full, correctly ordered log '
      'history across the current file and its numbered backups', () {
    final path = '${tempDir.path}/rotating.log';
    // maxBackups is generous on purpose: it must exceed how many rotations
    // 60 tiny entries trigger at this maxSizeBytes, so nothing gets pruned
    // and the full history is reconstructible. Retention limiting itself
    // (deleting the oldest backup once maxBackups is exceeded) is already
    // covered as a unit concern; this test is about ordering across
    // rotation, not retention.
    const maxBackups = 100;
    StructlogConfiguration.configure(
      output:
          rotatingFileOutput(path, maxSizeBytes: 200, maxBackups: maxBackups),
    );

    final log = getLogger();
    for (var i = 0; i < 60; i++) {
      log.info('iteration', context: {'i': i});
    }

    // Oldest entries live in the highest-numbered backup; reconstruct the
    // full timeline oldest-to-newest across every rotated file plus the
    // current one.
    final backups = <File>[];
    for (var i = maxBackups - 1; i >= 0; i--) {
      final f = File('$path.$i');
      if (f.existsSync()) backups.add(f);
    }
    final allFiles = [...backups, File(path)];

    final indices = allFiles
        .expand((f) => f.readAsLinesSync())
        .map((l) => jsonDecode(l)['i'] as int)
        .toList();

    expect(indices, List.generate(60, (i) => i));
  });

  test(
      'async rotating file output preserves the full, correctly ordered log '
      'history the same way its sync counterpart does', () async {
    final path = '${tempDir.path}/async_rotating.log';
    // See the sync rotation test above for why maxBackups is generous here.
    const maxBackups = 100;
    final asyncOutput = AsyncRotatingFileOutput(
      path,
      maxSizeBytes: 200,
      maxBackups: maxBackups,
    );
    StructlogConfiguration.configure(output: asyncOutput);

    final log = getLogger();
    for (var i = 0; i < 60; i++) {
      log.info('iteration', context: {'i': i});
    }
    await asyncOutput.flushed;

    final backups = <File>[];
    for (var i = maxBackups - 1; i >= 0; i--) {
      final f = File('$path.$i');
      if (f.existsSync()) backups.add(f);
    }
    final allFiles = [...backups, File(path)];

    final indices = allFiles
        .expand((f) => f.readAsLinesSync())
        .map((l) => jsonDecode(l)['i'] as int)
        .toList();

    expect(indices, List.generate(60, (i) => i));
  });

  test(
      'coloredConsoleOutput produces the documented format when driven '
      'through a real BoundLogger call, not called directly', () async {
    final lines = <String>[];

    await runZoned(() async {
      StructlogConfiguration.configure(output: coloredConsoleOutput);
      final log = getLogger().bind({'user_id': 42});
      log.error('payment_failed', context: {'reason': 'timeout'});
    },
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => lines.add(line),
        ));

    expect(lines, hasLength(1));
    final line = lines.single;
    expect(line, contains('ERROR: payment_failed'));
    expect(line, contains('"user_id":42'));
    expect(line, contains('"reason":"timeout"'));
    // event/level/timestamp are stripped from the trailing context blob.
    expect(line, isNot(contains('"event"')));
  });
}
