import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:shelf/shelf.dart';
import 'package:structured_log_server/src/auth/hashing.dart';
import 'package:structured_log_server/src/http/project_key_middleware.dart';
import 'package:structured_log_server/src/storage/database.dart';
import 'package:test/test.dart';

StructuredLogDatabase openInMemory() {
  return StructuredLogDatabase(
    NativeDatabase.memory(
      setup: (db) => db.execute('PRAGMA foreign_keys=ON;'),
    ),
  );
}

void main() {
  late StructuredLogDatabase db;
  late int projectId;
  late String plainKey;

  setUp(() async {
    db = openInMemory();
    final groupId = await db.into(db.groups).insert(
          GroupsCompanion.insert(name: 'g'),
        );
    projectId = await db.into(db.projects).insert(
          ProjectsCompanion.insert(
              groupId: groupId, name: 'p', retentionDays: 30),
        );
    plainKey = generateRandomToken();
    await db.into(db.projectSecretKeys).insert(
          ProjectSecretKeysCompanion.insert(
            projectId: projectId,
            keyHash: hashToken(plainKey),
            label: const Value('test key'),
          ),
        );
  });
  tearDown(() => db.close());

  test('a request without an Authorization header is rejected with 401',
      () async {
    final handler = const Pipeline()
        .addMiddleware(projectKeyMiddleware(db))
        .addHandler((req) => Response.ok('ok'));

    final response =
        await handler(Request('POST', Uri.parse('http://x/v1/logs')));
    expect(response.statusCode, 401);
  });

  test('an unknown key is rejected with 401', () async {
    final handler = const Pipeline()
        .addMiddleware(projectKeyMiddleware(db))
        .addHandler((req) => Response.ok('ok'));

    final response = await handler(
      Request(
        'POST',
        Uri.parse('http://x/v1/logs'),
        headers: {'authorization': 'Bearer not-a-real-key'},
      ),
    );
    expect(response.statusCode, 401);
  });

  test('a revoked key is rejected with 401', () async {
    await (db.update(
      db.projectSecretKeys,
    )..where((t) => t.projectId.equals(projectId)))
        .write(
      ProjectSecretKeysCompanion(revokedAt: Value(DateTime.now())),
    );

    final handler = const Pipeline()
        .addMiddleware(projectKeyMiddleware(db))
        .addHandler((req) => Response.ok('ok'));

    final response = await handler(
      Request(
        'POST',
        Uri.parse('http://x/v1/logs'),
        headers: {'authorization': 'Bearer $plainKey'},
      ),
    );
    expect(response.statusCode, 401);
  });

  test('a valid key reaches the inner handler with the resolved project id',
      () async {
    late int seenByHandler;
    final handler = const Pipeline()
        .addMiddleware(projectKeyMiddleware(db))
        .addHandler((req) {
      seenByHandler = req.authenticatedProjectId;
      return Response.ok('ok');
    });

    final response = await handler(
      Request(
        'POST',
        Uri.parse('http://x/v1/logs'),
        headers: {'authorization': 'Bearer $plainKey'},
      ),
    );

    expect(response.statusCode, 200);
    expect(seenByHandler, projectId);
  });
}
