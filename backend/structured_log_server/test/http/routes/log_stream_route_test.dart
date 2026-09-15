import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:shelf/shelf.dart';
import 'package:structured_log_server/src/auth/hashing.dart';
import 'package:structured_log_server/src/http/server.dart';
import 'package:structured_log_server/src/live/log_broadcast.dart';
import 'package:structured_log_server/src/storage/database.dart';
import 'package:test/test.dart';

StructuredLogDatabase openInMemory() {
  return StructuredLogDatabase(
    NativeDatabase.memory(
      setup: (db) => db.execute('PRAGMA foreign_keys=ON;'),
    ),
  );
}

/// One decoded SSE frame. `comment` is a keep-alive; the rest carry a
/// payload.
typedef SseFrame = ({int? id, String? event, String data, bool comment});

/// Reads an `event-stream` response body incrementally, the way a client
/// does — the test can't collect the whole body, since the point of the
/// endpoint is that it never ends on its own.
class StreamReader {
  final frames = <SseFrame>[];
  late final StreamSubscription<List<int>> _subscription;
  var _buffer = '';
  var _done = false;

  StreamReader(Response response) {
    _subscription = response.read().listen(
          _onChunk,
          onDone: () => _done = true,
          onError: (_) => _done = true,
        );
  }

  void _onChunk(List<int> chunk) {
    _buffer += utf8.decode(chunk);
    while (true) {
      final end = _buffer.indexOf('\n\n');
      if (end < 0) return;
      final raw = _buffer.substring(0, end);
      _buffer = _buffer.substring(end + 2);
      frames.add(_parse(raw));
    }
  }

  static SseFrame _parse(String raw) {
    if (raw.startsWith(':')) {
      return (
        id: null,
        event: null,
        data: raw.substring(1).trim(),
        comment: true
      );
    }
    int? id;
    String? event;
    final data = <String>[];
    for (final line in raw.split('\n')) {
      if (line.startsWith('id: ')) {
        id = int.tryParse(line.substring(4));
      } else if (line.startsWith('event: ')) {
        event = line.substring(7);
      } else if (line.startsWith('data: ')) {
        data.add(line.substring(6));
      }
    }
    return (id: id, event: event, data: data.join('\n'), comment: false);
  }

  List<SseFrame> get events => frames.where((f) => !f.comment).toList();
  List<SseFrame> get logs => events.where((f) => f.event == 'log').toList();
  List<String> get eventTexts =>
      logs.map((f) => jsonDecode(f.data)['event'] as String).toList();
  List<int> get ids => logs.map((f) => f.id!).toList();
  SseFrame? get end => events.where((f) => f.event == 'end').firstOrNull;
  bool get isDone => _done;

  /// Waits until [test] holds or the budget runs out. The stream is driven
  /// by real timers and microtasks, so there is nothing to await directly.
  Future<void> waitFor(
    bool Function() test, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!test()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('timed out waiting; frames so far: $frames');
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  /// Gives the stream a chance to deliver something that should NOT arrive.
  static Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 120));

  Future<void> close() => _subscription.cancel();
}

void main() {
  late StructuredLogDatabase db;
  late LogBroadcast broadcast;
  late Handler handler;
  late int userId;
  late int groupId;
  late int projectId;
  late int otherProjectId;
  late String accessToken;
  late String secretKey;
  final readers = <StreamReader>[];

  /// Everything the suite needs: an admin who can read, a group with two
  /// projects, and an ingest key for the first.
  setUp(() async {
    db = openInMemory();
    broadcast = LogBroadcast();
    handler = buildHandler(
      db,
      signingSecret: 'test-secret',
      issuer: 'test',
      broadcast: broadcast,
      // Short enough that revalidation is observable inside a test.
      sseHeartbeatInterval: const Duration(milliseconds: 60),
    );

    userId = await db.into(db.users).insert(
          UsersCompanion.insert(
            username: 'root',
            passwordHash: hashPassword('s3cret'),
          ),
        );
    await db.into(db.roleAssignments).insert(
          RoleAssignmentsCompanion.insert(
            subjectType: 'user',
            subjectId: userId,
            role: 'admin',
            scopeType: 'global',
          ),
        );
    groupId =
        await db.into(db.groups).insert(GroupsCompanion.insert(name: 'g'));
    projectId = await db.into(db.projects).insert(
          ProjectsCompanion.insert(
            groupId: groupId,
            name: 'p',
            retentionDays: 30,
          ),
        );
    otherProjectId = await db.into(db.projects).insert(
          ProjectsCompanion.insert(
            groupId: groupId,
            name: 'p2',
            retentionDays: 30,
          ),
        );
    for (final id in [projectId, otherProjectId]) {
      await db.into(db.projectUsage).insert(
            ProjectUsageCompanion.insert(projectId: Value(id)),
          );
    }
    secretKey = generateProjectSecretKey();
    await db.into(db.projectSecretKeys).insert(
          ProjectSecretKeysCompanion.insert(
            projectId: projectId,
            keyHash: hashToken(secretKey),
            label: const Value('ingest'),
          ),
        );

    final tokenResponse = await handler(
      Request(
        'POST',
        Uri.parse('http://x/v1/auth/token'),
        body: 'grant_type=password&username=root&password=s3cret',
        headers: {'content-type': 'application/x-www-form-urlencoded'},
      ),
    );
    final tokenBody =
        jsonDecode(await tokenResponse.readAsString()) as Map<String, Object?>;
    accessToken = tokenBody['access_token'] as String;
  });

  tearDown(() async {
    // Before the database: an open subscription re-checks authorization on
    // a timer, and closing the database under it would have it query a
    // closed connection.
    for (final reader in readers) {
      await reader.close();
    }
    readers.clear();
    await broadcast.close();
    await db.close();
  });

  Future<Response> subscribe(String query, {String? token}) async {
    return handler(
      Request(
        'GET',
        Uri.parse('http://x/v1/logs/stream?$query'),
        headers: {'authorization': 'Bearer ${token ?? accessToken}'},
      ),
    );
  }

  /// Mints an access token for a freshly created user with no roles.
  Future<String> tokenForRolelessUser() async {
    await db.into(db.users).insert(
          UsersCompanion.insert(
            username: 'nobody',
            passwordHash: hashPassword('pw'),
          ),
        );
    final response = await handler(
      Request(
        'POST',
        Uri.parse('http://x/v1/auth/token'),
        body: 'grant_type=password&username=nobody&password=pw',
        headers: {'content-type': 'application/x-www-form-urlencoded'},
      ),
    );
    final decoded =
        jsonDecode(await response.readAsString()) as Map<String, Object?>;
    return decoded['access_token'] as String;
  }

  /// Opens a subscription and registers it for teardown.
  Future<StreamReader> open(String query) async {
    final response = await subscribe(query);
    expect(response.statusCode, 200, reason: 'subscription was rejected');
    final reader = StreamReader(response);
    readers.add(reader);
    return reader;
  }

  /// Ingests through the real `POST /v1/logs` path, so entries reach the
  /// broadcast exactly as they do in production.
  Future<void> ingest(
    List<Map<String, Object?>> entries, {
    String? key,
  }) async {
    final response = await handler(
      Request(
        'POST',
        Uri.parse('http://x/v1/logs'),
        body: jsonEncode(entries),
        headers: {'authorization': 'Bearer ${key ?? secretKey}'},
      ),
    );
    expect(response.statusCode, 202, reason: await response.readAsString());
  }

  Map<String, Object?> entry(String event, {String level = 'info'}) => {
        'event': event,
        'level': level,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      };

  group('authorization happens before the stream opens', () {
    test('a caller without a covering role gets a plain 403', () async {
      // A token carries a snapshot of its holder's roles, so revoking a
      // role assignment can't be simulated by deleting the row — that is
      // what token_version is for. A user who never had a role is the
      // honest way to express "no covering role".
      final response = await subscribe(
        'project_id=$projectId',
        token: await tokenForRolelessUser(),
      );

      expect(response.statusCode, 403);
      expect(response.headers['content-type'], contains('application/json'));
    });

    test('an unknown project is 404', () async {
      final response = await subscribe('project_id=999999');
      expect(response.statusCode, 404);
    });

    test('an unknown group is 404', () async {
      final response = await subscribe('group_id=999999');
      expect(response.statusCode, 404);
    });

    test('neither project_id nor group_id is 400', () async {
      final response = await subscribe('level=info');
      expect(response.statusCode, 400);
    });

    test('a blocked project is 403 project_blocked, with no stream', () async {
      await (db.update(db.projects)..where((t) => t.id.equals(projectId)))
          .write(const ProjectsCompanion(isBlocked: Value(true)));

      final response = await subscribe('project_id=$projectId');
      expect(response.statusCode, 403);
      final body =
          jsonDecode(await response.readAsString()) as Map<String, Object?>;
      expect(body['error'], 'project_blocked');
    });

    test('an authorized subscription opens as an event-stream', () async {
      final response = await subscribe('project_id=$projectId');
      expect(response.statusCode, 200);
      expect(response.headers['content-type'], contains('text/event-stream'));
      readers.add(StreamReader(response));
    });
  });

  group('delivery', () {
    test('an entry accepted after subscribing is delivered', () async {
      final reader = await open('project_id=$projectId');

      await ingest([entry('hello')]);
      await reader.waitFor(() => reader.logs.isNotEmpty);

      expect(reader.eventTexts, ['hello']);
      expect(reader.logs.single.id, isNotNull);
    });

    test('nothing accepted before subscribing is delivered', () async {
      await ingest([entry('before')]);

      final reader = await open('project_id=$projectId');

      await ingest([entry('after')]);
      await reader.waitFor(() => reader.logs.isNotEmpty);
      await StreamReader.settle();

      expect(reader.eventTexts, ['after']);
    });

    test('entries of another project are not delivered', () async {
      final otherKey = generateProjectSecretKey();
      await db.into(db.projectSecretKeys).insert(
            ProjectSecretKeysCompanion.insert(
              projectId: otherProjectId,
              keyHash: hashToken(otherKey),
            ),
          );

      final reader = await open('project_id=$projectId');

      await ingest([entry('elsewhere')], key: otherKey);
      await ingest([entry('mine')]);
      await reader.waitFor(() => reader.logs.isNotEmpty);
      await StreamReader.settle();

      expect(reader.eventTexts, ['mine']);
    });
  });

  group('shutting down', () {
    test('closing the broadcast ends every open subscription', () async {
      final reader = await open('project_id=$projectId');

      // What `bin/server.dart` does first on SIGTERM. Until this ended the
      // response, `HttpServer.close(force: false)` waited for a connection
      // that never finishes, and the process sat on the signal until
      // something killed it.
      await broadcast.close();
      await reader.waitFor(
        () => reader.frames.any((frame) => frame.event == 'end'),
      );

      final terminal = reader.frames.last;
      expect(terminal.event, 'end');
      expect(
        jsonDecode(terminal.data),
        {'reason': 'server_shutdown'},
        reason: 'a subscriber is told why, rather than left with a socket '
            'that stopped answering — and the reason says it is worth '
            'reconnecting once the server is back',
      );
    });
  });

  group('filtering', () {
    test('an entry below the level filter is not delivered', () async {
      final reader = await open('project_id=$projectId&level=warning');

      await ingest([entry('quiet', level: 'debug')]);
      await StreamReader.settle();

      expect(reader.logs, isEmpty);
    });

    test('an entry passing the filter is delivered immediately', () async {
      final reader = await open('project_id=$projectId&level=warning');

      await ingest([
        entry('quiet', level: 'debug'),
        entry('loud', level: 'error'),
      ]);
      await reader.waitFor(() => reader.logs.isNotEmpty);
      await StreamReader.settle();

      expect(reader.eventTexts, ['loud']);
    });

    test('an unknown level is rejected with 400, not silently ignored',
        () async {
      final response = await subscribe('project_id=$projectId&level=bogus');
      expect(response.statusCode, 400);
    });
  });

  group('group scope', () {
    test('aggregates every project of the group', () async {
      final otherKey = generateProjectSecretKey();
      await db.into(db.projectSecretKeys).insert(
            ProjectSecretKeysCompanion.insert(
              projectId: otherProjectId,
              keyHash: hashToken(otherKey),
            ),
          );

      final reader = await open('group_id=$groupId');

      await ingest([entry('from-p1')]);
      await ingest([entry('from-p2')], key: otherKey);
      await reader.waitFor(() => reader.logs.length == 2);

      expect(reader.eventTexts, containsAll(['from-p1', 'from-p2']));
    });

    test('silently excludes a blocked project instead of ending', () async {
      final otherKey = generateProjectSecretKey();
      await db.into(db.projectSecretKeys).insert(
            ProjectSecretKeysCompanion.insert(
              projectId: otherProjectId,
              keyHash: hashToken(otherKey),
            ),
          );

      final reader = await open('group_id=$groupId');

      // Blocking after the subscription opened: ingestion for the blocked
      // project is refused outright, and the subscription must survive.
      await (db.update(db.projects)..where((t) => t.id.equals(otherProjectId)))
          .write(const ProjectsCompanion(isBlocked: Value(true)));

      await ingest([entry('still-visible')]);
      await reader.waitFor(() => reader.logs.isNotEmpty);
      await StreamReader.settle();

      expect(reader.eventTexts, ['still-visible']);
      expect(reader.end, isNull, reason: 'a group subscription must not end');
    });
  });

  group('catch-up by since_id', () {
    test('delivers what was missed, then continues live', () async {
      await ingest([entry('e1'), entry('e2')]);
      final stored = await db.select(db.logEntries).get();
      final firstId = stored.first.id;

      final reader = await open('project_id=$projectId&since_id=$firstId');

      await reader.waitFor(() => reader.logs.isNotEmpty);
      await ingest([entry('e3')]);
      await reader.waitFor(() => reader.logs.length == 2);

      expect(reader.eventTexts, ['e2', 'e3']);
    });

    test('delivers nothing twice when a batch lands during catch-up', () async {
      await ingest([for (var i = 0; i < 20; i++) entry('old-$i')]);
      final stored = await db.select(db.logEntries).get();
      final sinceId = stored[9].id;

      final reader = await open('project_id=$projectId&since_id=$sinceId');

      // Straight into the window the buffer exists for: this batch may be
      // both read back by the catch-up query and broadcast to the new
      // subscriber.
      await ingest([entry('racing')]);

      await reader.waitFor(() => reader.eventTexts.contains('racing'));
      await StreamReader.settle();

      expect(reader.ids, reader.ids.toSet().toList(), reason: 'no duplicates');
      expect(reader.ids, orderedEquals(reader.ids.toList()..sort()));
      expect(reader.eventTexts.length, 11, reason: '10 missed + 1 new');
      expect(reader.eventTexts.last, 'racing');
    });

    test('an unparsable since_id is 400', () async {
      final response =
          await subscribe('project_id=$projectId&since_id=not-a-number');
      expect(response.statusCode, 400);
    });

    test('catch-up respects the filter', () async {
      await ingest([
        entry('noisy', level: 'debug'),
        entry('urgent', level: 'error'),
      ]);

      final reader =
          await open('project_id=$projectId&since_id=0&level=warning');

      await reader.waitFor(() => reader.logs.isNotEmpty);
      await StreamReader.settle();

      expect(reader.eventTexts, ['urgent']);
    });
  });

  group('heartbeat and revalidation', () {
    test('a valid connection receives keep-alives and stays open', () async {
      final reader = await open('project_id=$projectId');

      await reader
          .waitFor(() => reader.frames.where((f) => f.comment).length >= 2);

      expect(reader.end, isNull);
      expect(reader.isDone, isFalse);
    });

    test('a token_version bump ends the connection', () async {
      final reader = await open('project_id=$projectId');

      await (db.update(db.users)..where((t) => t.id.equals(userId))).write(
        const UsersCompanion(tokenVersion: Value(99)),
      );

      await reader.waitFor(() => reader.end != null);
      expect(jsonDecode(reader.end!.data)['reason'], 'token_revoked');
      await reader.waitFor(() => reader.isDone);
    });

    test('deactivating the user ends the connection', () async {
      final reader = await open('project_id=$projectId');

      await (db.update(db.users)..where((t) => t.id.equals(userId))).write(
        const UsersCompanion(isActive: Value(false)),
      );

      await reader.waitFor(() => reader.end != null);
      expect(jsonDecode(reader.end!.data)['reason'], 'token_revoked');
    });

    test('blocking the subscribed project ends the connection', () async {
      final reader = await open('project_id=$projectId');

      await (db.update(db.projects)..where((t) => t.id.equals(projectId)))
          .write(const ProjectsCompanion(isBlocked: Value(true)));

      await reader.waitFor(() => reader.end != null);
      expect(jsonDecode(reader.end!.data)['reason'], 'project_blocked');
    });
  });
}
