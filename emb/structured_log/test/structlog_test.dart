import 'dart:convert';
import 'dart:io';

import 'package:structured_log/structured_log.dart';
import 'package:test/test.dart';

void main() {
  group('BoundLogger', () {
    test('bind adds context to log entries', () {
      final log = getLogger().bind({'key': 'value'});
      expect(log, isA<BoundLogger>());
    });

    test('unbind removes keys from context', () {
      final log = getLogger().bind({'key1': 'a', 'key2': 'b'});
      final unbound = log.unbind(['key1']);
      expect(unbound, isA<BoundLogger>());
    });

    test('log levels work correctly', () {
      final log = getLogger();
      log.trace('test');
      log.debug('test');
      log.info('test');
      log.warning('test');
      log.error('test');
      log.critical('test');
    });
  });

  group('Configuration', () {
    tearDown(() {
      StructlogConfiguration.reset();
    });

    test('configure updates settings', () {
      StructlogConfiguration.configure(
        initialContext: {'app': 'test'},
      );
      expect(StructlogConfiguration.current.initialContext['app'], 'test');
    });

    test('reset restores defaults', () {
      StructlogConfiguration.configure(
        initialContext: {'app': 'test'},
      );
      StructlogConfiguration.reset();
      expect(StructlogConfiguration.current.initialContext, isEmpty);
    });

    test('initialContext is applied to every logger entry', () {
      Map<String, dynamic>? captured;
      StructlogConfiguration.configure(
        initialContext: {'app': 'my_app', 'version': '1.0.0'},
        output: (entry, level) => captured = entry,
      );

      getLogger().info('event');

      expect(captured!['app'], 'my_app');
      expect(captured!['version'], '1.0.0');
    });

    test(
        'bind() and inline context override an initialContext key with the '
        'same name', () {
      Map<String, dynamic>? captured;
      StructlogConfiguration.configure(
        initialContext: {'app': 'my_app'},
        output: (entry, level) => captured = entry,
      );

      getLogger().bind({'app': 'from_bind'}).info(
        'event',
        context: {'app': 'from_inline'},
      );

      expect(captured!['app'], 'from_inline');
    });
  });

  group('Processors', () {
    test('dropNullValues removes null entries', () {
      final entry = {'a': 1, 'b': null, 'c': 'test'};
      final result = dropNullValues(entry);
      expect(result, isNotNull);
      expect(result!.containsKey('b'), isFalse);
    });
  });

  group('redactKeys', () {
    tearDown(StructlogConfiguration.reset);

    test('a key in the default set is replaced, not removed', () {
      final entry = redactKeys()({'event': 'login', 'password': 'hunter2'})!;
      expect(entry['password'], '***');
      expect(
        entry.containsKey('password'),
        isTrue,
        reason: 'the reader has to be able to tell redacted from absent',
      );
      expect(entry['event'], 'login');
    });

    test('matching ignores case, because headers do not agree on it', () {
      final entry =
          redactKeys()({'Authorization': 'Bearer x', 'API_Key': 'k'})!;
      expect(entry['Authorization'], '***');
      expect(entry['API_Key'], '***');
    });

    test('a value of any type is replaced when its key matches', () {
      final entry = redactKeys(keys: {'pin'})({'pin': 1234})!;
      expect(entry['pin'], '***');
    });

    test('nested maps and lists are reached', () {
      final entry = redactKeys()({
        'request': {
          'headers': [
            {'authorization': 'Bearer x'},
            {'accept': 'application/json'},
          ],
        },
      })!;
      final headers =
          ((entry['request'] as Map)['headers'] as List).cast<Map>();
      expect(headers[0]['authorization'], '***');
      expect(headers[1]['accept'], 'application/json');
    });

    test('the caller keeps its own data', () {
      // The reason this belongs in the library at all: the obvious
      // implementation walks and assigns, and `Map.from` is shallow, so a
      // nested map in the entry is the *same object* the application is
      // still using. Logging must not take the caller's token away.
      final headers = <String, dynamic>{'authorization': 'Bearer real'};
      final captured = <Map<String, dynamic>>[];
      StructlogConfiguration.configure(
        processors: [redactKeys()],
        sinks: [LogSink(name: 'capture', output: (e, l) => captured.add(e))],
      );

      getLogger().bind({'headers': headers}).info('request');

      expect((captured.single['headers'] as Map)['authorization'], '***');
      expect(headers['authorization'], 'Bearer real');
    });

    test('an entry with nothing to redact comes back as the same map', () {
      // Processors run before any sink filtering, so every dropped trace
      // entry pays for this walk too. A miss must not allocate a copy.
      final entry = <String, dynamic>{
        'event': 'tick',
        'nested': {'a': 1},
      };
      final result = redactKeys()(entry);
      expect(identical(result, entry), isTrue);
      expect(identical(result!['nested'], entry['nested']), isTrue);
    });

    test('an explicit key set replaces the default one', () {
      final entry = redactKeys(keys: {'ssn'})({
        'ssn': '1',
        'password': 'hunter2',
      })!;
      expect(entry['ssn'], '***');
      expect(
        entry['password'],
        'hunter2',
        reason: 'passing keys means these keys, not these as well as ours',
      );
    });

    test('an empty key set turns name matching off', () {
      final entry = redactKeys(keys: const {})({'password': 'hunter2'})!;
      expect(entry['password'], 'hunter2');
    });

    test('a key predicate catches a family of names', () {
      final entry = redactKeys(
        keys: const {},
        matchesKey: (key) => key.endsWith('_token'),
      )({'refresh_token': 'r', 'token_count': 3})!;
      expect(entry['refresh_token'], '***');
      expect(entry['token_count'], 3);
    });

    test('a value predicate catches a secret under an innocent name', () {
      final entry = redactKeys(
        keys: const {},
        matchesValue: looksLikeJwtOrBearer,
      )({
        'note': 'Bearer abc.def.ghi',
        'other': 'plain text',
      })!;
      expect(entry['note'], '***');
      expect(entry['other'], 'plain text');
    });

    test('a value predicate is asked about strings only', () {
      var asked = 0;
      redactKeys(
        keys: const {},
        matchesValue: (value) {
          asked++;
          return false;
        },
      )({'n': 42, 's': 'text', 'nested': <String, dynamic>{}});
      expect(asked, 1, reason: 'guessing at an int costs everything it finds');
    });

    test('the three criteria combine, and any one of them is enough', () {
      final entry = redactKeys(
        keys: {'password'},
        matchesKey: (key) => key.endsWith('_token'),
        matchesValue: looksLikeJwtOrBearer,
      )({
        'password': 'hunter2',
        'refresh_token': 'r',
        'note': 'Bearer abc.def.ghi',
        'kept': 'plain',
      })!;
      expect(entry['password'], '***');
      expect(entry['refresh_token'], '***');
      expect(entry['note'], '***');
      expect(entry['kept'], 'plain');
    });

    test('a caller may choose the placeholder', () {
      final entry = redactKeys(placeholder: '[redacted]')({'token': 't'})!;
      expect(entry['token'], '[redacted]');
    });

    test('looksLikeJwtOrBearer knows a token from a sentence', () {
      expect(looksLikeJwtOrBearer('Bearer abc'), isTrue);
      expect(looksLikeJwtOrBearer('bearer abc'), isTrue);
      expect(
        looksLikeJwtOrBearer(
          'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.c2ln',
        ),
        isTrue,
      );
      expect(looksLikeJwtOrBearer('a normal message'), isFalse);
      expect(looksLikeJwtOrBearer('bearers of bad news'), isFalse);
    });

    test('looksLikeCardNumber is opt-in and checks Luhn', () {
      expect(looksLikeCardNumber('4111 1111 1111 1111'), isTrue);
      expect(looksLikeCardNumber('4111-1111-1111-1111'), isTrue);
      expect(
        looksLikeCardNumber('4111111111111112'),
        isFalse,
        reason: 'Luhn is what keeps order ids out of this',
      );
      expect(looksLikeCardNumber('ord_44821'), isFalse);
      expect(looksLikeCardNumber('12345678'), isFalse);
      expect(
        redactKeys()({'note': '4111 1111 1111 1111'})!['note'],
        '4111 1111 1111 1111',
        reason: 'it is not in the defaults — false positives cost data',
      );
    });

    test('the correlation fields survive the default set', () {
      // They are the one kind of identifier this package produces for the
      // express purpose of being read back. A default that swallowed them
      // would break the feature next door while looking careful.
      final entry = redactKeys()({
        'session_id': 's-1',
        'request_id': 'r-1',
        'operation_id': 'o-1',
      })!;
      expect(entry['session_id'], 's-1');
      expect(entry['request_id'], 'r-1');
      expect(entry['operation_id'], 'o-1');
    });

    test('defaultSensitiveKeys names what it protects', () {
      expect(
        defaultSensitiveKeys,
        containsAll(<String>['password', 'token', 'secret', 'authorization']),
      );
    });
  });

  group('Correlation', () {
    tearDown(() {
      StructlogConfiguration.reset();
    });

    test('all 6 fields serialize under fixed snake_case keys', () {
      Map<String, dynamic>? captured;
      StructlogConfiguration.configure(
        output: (entry, level) => captured = entry,
      );

      getLogger()
          .withCorrelation(
            sessionId: 's-14',
            requestId: 'r-42',
            connectionGeneration: 8,
            toolCallId: 'tc-3',
            messageId: 'm-1',
            operationId: 'op-9',
          )
          .info('event');

      expect(captured, isNotNull);
      expect(captured!['session_id'], 's-14');
      expect(captured!['request_id'], 'r-42');
      expect(captured!['connection_generation'], 8);
      expect(captured!['tool_call_id'], 'tc-3');
      expect(captured!['message_id'], 'm-1');
      expect(captured!['operation_id'], 'op-9');
    });

    test('child logger inherits and can override without mutating parent', () {
      final captures = <Map<String, dynamic>>[];
      StructlogConfiguration.configure(
        output: (entry, level) => captures.add(entry),
      );

      final parent =
          getLogger().withCorrelation(sessionId: 's-14', requestId: 'r-42');
      final child = parent.withCorrelation(toolCallId: 'tc-3');

      parent.info('parent_event');
      child.info('child_event');

      final parentEntry =
          captures.firstWhere((e) => e['event'] == 'parent_event');
      final childEntry =
          captures.firstWhere((e) => e['event'] == 'child_event');

      expect(parentEntry.containsKey('tool_call_id'), isFalse);
      expect(childEntry['session_id'], 's-14');
      expect(childEntry['request_id'], 'r-42');
      expect(childEntry['tool_call_id'], 'tc-3');
    });

    test('typed correlation field wins over same-named map context key', () {
      Map<String, dynamic>? captured;
      StructlogConfiguration.configure(
        output: (entry, level) => captured = entry,
      );

      getLogger().withCorrelation(sessionId: 'typed').info(
        'event',
        context: {'session_id': 'from_map'},
      );

      expect(captured!['session_id'], 'typed');
    });
  });

  group('Sinks', () {
    tearDown(() {
      StructlogConfiguration.reset();
    });

    test('one entry passing multiple sinks is delivered to all of them', () {
      final a = <Map<String, dynamic>>[];
      final b = <Map<String, dynamic>>[];
      StructlogConfiguration.configure(sinks: [
        LogSink(name: 'a', output: (entry, level) => a.add(entry)),
        LogSink(name: 'b', output: (entry, level) => b.add(entry)),
      ]);

      getLogger().info('event');

      expect(a, hasLength(1));
      expect(b, hasLength(1));
    });

    test('minLevel filters out lower-level entries per sink', () {
      final debugSink = <Map<String, dynamic>>[];
      final errorSink = <Map<String, dynamic>>[];
      StructlogConfiguration.configure(sinks: [
        LogSink(name: 'debug', output: (e, l) => debugSink.add(e)),
        LogSink(
          name: 'error',
          output: (e, l) => errorSink.add(e),
          minLevel: LogLevel.error,
        ),
      ]);

      final log = getLogger();
      log.info('low');
      log.error('high');

      expect(debugSink, hasLength(2));
      expect(errorSink, hasLength(1));
      expect(errorSink.single['event'], 'high');
    });

    test(
        "trace is below a sink's default minLevel (debug) and is filtered "
        'out unless a sink explicitly opts in', () {
      final defaultSink = <Map<String, dynamic>>[];
      final traceSink = <Map<String, dynamic>>[];
      StructlogConfiguration.configure(sinks: [
        LogSink(name: 'default', output: (e, l) => defaultSink.add(e)),
        LogSink(
          name: 'trace',
          output: (e, l) => traceSink.add(e),
          minLevel: LogLevel.trace,
        ),
      ]);

      final log = getLogger();
      log.trace('raw_frame');
      log.debug('normal');

      expect(defaultSink, hasLength(1));
      expect(defaultSink.single['event'], 'normal');
      expect(traceSink, hasLength(2));
    });

    test('categories filter routes entries by the category context key', () {
      final protocolSink = <Map<String, dynamic>>[];
      final appSink = <Map<String, dynamic>>[];
      StructlogConfiguration.configure(sinks: [
        LogSink(
          name: 'protocol',
          output: (e, l) => protocolSink.add(e),
          categories: {'protocol'},
        ),
        LogSink(name: 'app', output: (e, l) => appSink.add(e)),
      ]);

      final log = getLogger();
      log.info('app_event');
      log.info('protocol_event', context: {'category': 'protocol'});

      expect(appSink, hasLength(2));
      expect(protocolSink, hasLength(1));
      expect(protocolSink.single['event'], 'protocol_event');
    });

    test('setSinkEnabled toggles a sink in the running configuration', () {
      final captured = <Map<String, dynamic>>[];
      StructlogConfiguration.configure(sinks: [
        LogSink(name: 'toggle', output: (e, l) => captured.add(e)),
      ]);

      final log = getLogger();
      StructlogConfiguration.setSinkEnabled('toggle', enabled: false);
      log.info('while_disabled');
      expect(captured, isEmpty);

      StructlogConfiguration.setSinkEnabled('toggle', enabled: true);
      log.info('while_enabled');
      expect(captured, hasLength(1));
    });

    test('a throwing sink does not block delivery to other sinks', () {
      final good = <Map<String, dynamic>>[];
      StructlogConfiguration.configure(sinks: [
        LogSink(
          name: 'bad',
          output: (e, l) => throw StateError('boom'),
        ),
        LogSink(name: 'good', output: (e, l) => good.add(e)),
      ]);

      expect(() => getLogger().info('event'), returnsNormally);
      expect(good, hasLength(1));
    });

    test('legacy single-output configure() still works as one default sink',
        () {
      final captured = <Map<String, dynamic>>[];
      StructlogConfiguration.configure(
        output: (entry, level) => captured.add(entry),
      );

      getLogger().info('event');

      expect(captured, hasLength(1));
    });
  });

  group('Async outputs', () {
    tearDown(() {
      StructlogConfiguration.reset();
    });

    test('writes entries in order and flushed completes once all are written',
        () async {
      final dir = Directory.systemTemp.createTempSync('structured_log_test_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/app.log';
      final asyncOutput = AsyncFileOutput(path);
      StructlogConfiguration.configure(output: asyncOutput);

      final log = getLogger();
      for (var i = 0; i < 5; i++) {
        log.info('event', context: {'i': i});
      }
      await asyncOutput.flushed;

      final lines = File(path).readAsLinesSync();
      expect(lines, hasLength(5));
      for (var i = 0; i < 5; i++) {
        expect(jsonDecode(lines[i])['i'], i);
      }
    });

    test('a failing write does not throw and the queue still resolves',
        () async {
      final dir = Directory.systemTemp.createTempSync('structured_log_test_');
      addTearDown(() => dir.deleteSync(recursive: true));
      // A path that is itself an existing directory can never be opened as
      // a file, so every write to it is guaranteed to fail.
      final badPath = '${dir.path}/not_a_file';
      Directory(badPath).createSync();
      final asyncOutput = AsyncFileOutput(badPath);
      StructlogConfiguration.configure(output: asyncOutput);

      final log = getLogger();
      log.info('one');
      log.info('two');

      await expectLater(asyncOutput.flushed, completes);
    });

    test('rotates when exceeding maxSizeBytes', () async {
      final dir = Directory.systemTemp.createTempSync('structured_log_test_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/rotating.log';
      final asyncOutput = AsyncRotatingFileOutput(path, maxSizeBytes: 100);
      StructlogConfiguration.configure(output: asyncOutput);

      final log = getLogger();
      for (var i = 0; i < 50; i++) {
        log.info('iteration', context: {'i': i});
      }
      await asyncOutput.flushed;

      expect(File('$path.0').existsSync(), isTrue);
    });
  });
}
