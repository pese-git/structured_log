import 'dart:convert';
import 'dart:io';

import 'package:structured_log/structured_log.dart';
import 'package:structured_log_remote_sync/structured_log_remote_sync.dart';
import 'package:test/test.dart';

void main() {
  late List<List<Map<String, dynamic>>> batches;
  late List<String> reports;

  RemoteSyncLogOutput outputWith({
    int batchSize = 10,
    String? serverUrl,
    bool fake = true,
  }) {
    batches = [];
    reports = [];
    final output = RemoteSyncLogOutput(
      serverUrl: serverUrl ?? 'http://example.invalid',
      projectSecretKey: 'slk_test',
      batchSize: batchSize,
      batchTimeout: const Duration(minutes: 1),
      sender: fake
          ? (entries) async {
              batches.add(entries);
              return const BatchResult.delivered();
            }
          : null,
      report: reports.add,
    );
    addTearDown(output.close);
    return output;
  }

  Map<String, dynamic> awkward(int i) => {
        'event': 'e$i',
        'at': DateTime.utc(2026, 10, 2),
        'cause': StateError('x'),
      };

  group('Values jsonEncode refuses', () {
    test('cost no entry of the batch', () async {
      final output = outputWith();

      for (var i = 0; i < 10; i++) {
        output(i == 4 ? awkward(i) : {'event': 'e$i'}, LogLevel.info);
      }
      await output.flushed;

      final sent = batches.single;
      expect(sent.map((e) => e['event']), [for (var i = 0; i < 10; i++) 'e$i']);
      expect(sent[4]['at'], '2026-10-02T00:00:00.000Z');
      expect(sent[4]['cause'], 'Bad state: x');
      expect(reports, isEmpty);
    });

    test('reach a real server, every entry of the batch with them', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final bodies = <String>[];
      server.listen((request) async {
        bodies.add(await utf8.decodeStream(request));
        request.response.statusCode = 202;
        await request.response.close();
      });
      final output = outputWith(
        serverUrl: 'http://localhost:${server.port}',
        fake: false,
      );

      for (var i = 0; i < 10; i++) {
        output(i == 4 ? awkward(i) : {'event': 'e$i'}, LogLevel.info);
      }
      await output.flushed;

      final sent = jsonDecode(bodies.single) as List;
      expect(sent, hasLength(10));
      expect((sent[4] as Map)['at'], '2026-10-02T00:00:00.000Z');
      expect(reports, isEmpty);
    });

    test('a cycle is sent as the stub encodeLogEntry makes', () async {
      final output = outputWith(batchSize: 2);
      final loop = <String, dynamic>{};
      loop['self'] = loop;

      output({'event': 'looped', 'loop': loop}, LogLevel.info);
      output({'event': 'fine'}, LogLevel.info);
      await output.flushed;

      expect(batches.single.first, {
        'event': 'looped',
        'encoding_failed': 'JsonCyclicError',
      });
      expect(batches.single.last, {'event': 'fine'});
    });
  });

  group('An entry is taken as it was when it was logged', () {
    test('a change the application makes afterwards does not travel', () async {
      final output = outputWith();
      final user = <String, dynamic>{'id': 1};

      output({'event': 'login', 'user': user}, LogLevel.info);
      user['id'] = 2;
      user['token'] = 'added later';
      await output.flushed;

      expect(batches.single.single['user'], {'id': 1});
    });
  });

  group('An entry that cannot be encoded at all', () {
    test('is dropped alone, and said so', () async {
      final output = outputWith(batchSize: 2);

      output(_UnreadableMap(), LogLevel.info);
      output({'event': 'one'}, LogLevel.info);
      output({'event': 'two'}, LogLevel.info);
      await output.flushed;

      expect(batches.single.map((e) => e['event']), ['one', 'two']);
      expect(reports.single, contains('could not be encoded'));
      expect(reports.single, contains('StateError'));
    });
  });
}

/// A map whose every read throws — beyond what encodeLogEntry can recover.
class _UnreadableMap implements Map<String, dynamic> {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('unread');
}
