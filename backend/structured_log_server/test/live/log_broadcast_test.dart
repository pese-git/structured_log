import 'package:drift/native.dart';
import 'package:structured_log_server/src/live/log_broadcast.dart';
import 'package:structured_log_server/src/storage/database.dart';
import 'package:structured_log_server/src/storage/log_store.dart';
import 'package:test/test.dart';

StructuredLogDatabase openInMemory() {
  return StructuredLogDatabase(
    NativeDatabase.memory(setup: (db) => db.execute('PRAGMA foreign_keys=ON;')),
  );
}

void main() {
  late StructuredLogDatabase db;
  late LogStore store;
  late int projectId;
  late LogBroadcast broadcast;

  setUp(() async {
    db = openInMemory();
    store = DriftLogStore(db);
    broadcast = LogBroadcast();
    final groupId = await db
        .into(db.groups)
        .insert(GroupsCompanion.insert(name: 'g'));
    projectId = await db
        .into(db.projects)
        .insert(
          ProjectsCompanion.insert(
            groupId: groupId,
            name: 'p',
            retentionDays: 30,
          ),
        );
  });
  tearDown(() async {
    await broadcast.close();
    await db.close();
  });

  Future<List<LogEntry>> store2(List<String> events) {
    return store.insertBatch(projectId, [
      for (final event in events)
        LogEntriesCompanion.insert(
          projectId: projectId,
          receivedAt: DateTime.utc(2026),
          timestamp: DateTime.utc(2026),
          level: 'info',
          event: event,
          sizeBytes: 1,
          contextJson: '{}',
        ),
    ]);
  }

  test('delivers published entries to a listener, in order', () async {
    final seen = <String>[];
    broadcast.stream.listen((e) => seen.add(e.event));

    broadcast.publish(await store2(['a', 'b', 'c']));
    await pumpEventQueue();

    expect(seen, ['a', 'b', 'c']);
  });

  test('delivers the same entry to every listener', () async {
    // Two concurrent subscriptions to the same project is the ordinary
    // case (two people watching the same log), so one listener must not
    // consume events out from under another.
    final first = <String>[];
    final second = <String>[];
    broadcast.stream.listen((e) => first.add(e.event));
    broadcast.stream.listen((e) => second.add(e.event));

    broadcast.publish(await store2(['x']));
    await pumpEventQueue();

    expect(first, ['x']);
    expect(second, ['x']);
  });

  test('publishing with no listeners is a no-op, not an error', () async {
    expect(broadcast.hasListeners, isFalse);
    broadcast.publish(await store2(['nobody-listening']));
    await pumpEventQueue();
  });

  test('a listener only sees what is published after it subscribes', () async {
    broadcast.publish(await store2(['before']));
    await pumpEventQueue();

    final seen = <String>[];
    broadcast.stream.listen((e) => seen.add(e.event));
    broadcast.publish(await store2(['after']));
    await pumpEventQueue();

    expect(seen, ['after']);
  });

  test('hasListeners reflects the current subscriptions', () async {
    expect(broadcast.hasListeners, isFalse);
    final subscription = broadcast.stream.listen((_) {});
    expect(broadcast.hasListeners, isTrue);
    await subscription.cancel();
    expect(broadcast.hasListeners, isFalse);
  });

  test('a cancelled listener stops receiving', () async {
    final seen = <String>[];
    final subscription = broadcast.stream.listen((e) => seen.add(e.event));
    await subscription.cancel();

    broadcast.publish(await store2(['gone']));
    await pumpEventQueue();

    expect(seen, isEmpty);
  });

  test('publishing after close is ignored rather than throwing', () async {
    // Shutdown closes the broadcast while ingestion may still be finishing
    // a commit; that must not turn into an unhandled error on the way out.
    final entries = await store2(['late']);
    await broadcast.close();

    expect(() => broadcast.publish(entries), returnsNormally);
  });

  test('closing ends open subscriptions', () async {
    var done = false;
    broadcast.stream.listen((_) {}, onDone: () => done = true);

    await broadcast.close();
    await pumpEventQueue();

    expect(done, isTrue);
  });
}
