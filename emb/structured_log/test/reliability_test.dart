import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:structured_log/src/report_print.dart';
import 'package:structured_log/src/timestamp.dart';
import 'package:structured_log/io.dart';
import 'package:structured_log/structured_log.dart';
import 'package:test/test.dart';

void main() {
  tearDown(StructlogConfiguration.reset);

  group('encodeLogEntry', () {
    test('writes a DateTime as ISO-8601 in UTC', () {
      final local = DateTime(2026, 10, 2, 12);
      final decoded = _decode(encodeLogEntry({'at': local}));

      expect(decoded['at'], local.toUtc().toIso8601String());
      expect(decoded['at'], endsWith('Z'));
    });

    test('writes an enum by name and a Duration in microseconds', () {
      final decoded = _decode(encodeLogEntry({
        'level_hint': LogLevel.warning,
        'took': const Duration(milliseconds: 3),
      }));

      expect(decoded['level_hint'], 'warning');
      expect(decoded['took'], 3000);
    });

    test('writes any other object through toString()', () {
      final decoded = _decode(encodeLogEntry({
        'cause': StateError('timeout'),
        'nested': {
          'uri': Uri.parse('https://example.com/a'),
          'items': [Object()],
        },
      }));

      expect(decoded['cause'], 'Bad state: timeout');
      expect(decoded['nested']['uri'], 'https://example.com/a');
      expect(decoded['nested']['items'], ["Instance of 'Object'"]);
    });

    test('names the type of a value whose toString() throws', () {
      final decoded = _decode(encodeLogEntry({'v': _ThrowingToString()}));

      expect(decoded['v'], '<_ThrowingToString>');
    });

    test('a cycle becomes a stub naming the failure', () {
      final loop = <String, dynamic>{};
      loop['self'] = loop;

      final decoded = _decode(encodeLogEntry({
        'event': 'e',
        'level': 'info',
        'timestamp': 't',
        'logger': 'payments',
        'category': 'http',
        'loop': loop,
      }));

      expect(decoded, {
        'event': 'e',
        'level': 'info',
        'timestamp': 't',
        'logger': 'payments',
        'category': 'http',
        'encoding_failed': 'JsonCyclicError',
      });
    });

    test('the stub keeps only string-valued identifying fields', () {
      final loop = <String, dynamic>{};
      loop['self'] = loop;

      final decoded = _decode(encodeLogEntry({
        'event': 'e',
        'category': 42,
        'password': 'p',
        'loop': loop,
      }));

      expect(decoded, {'event': 'e', 'encoding_failed': 'JsonCyclicError'});
    });

    test('indent pretty-prints', () {
      expect(encodeLogEntry({'a': 1}, indent: '  '), '{\n  "a": 1\n}');
    });

    test('writes an object with toJson() as what toJson() returns', () {
      final decoded = _decode(encodeLogEntry({
        'user': _User('alice', DateTime.utc(2026, 10, 5)),
      }));

      expect(decoded['user'], {
        'name': 'alice',
        'joined': '2026-10-05T00:00:00.000Z',
      });
    });

    test('a toJson() that throws costs the value its JSON, not the entry', () {
      final decoded = _decode(encodeLogEntry({'v': _ThrowingToJson()}));

      expect(decoded['v'], 'throwing toJson');
    });

    test('writes a Set as a JSON array', () {
      final decoded = _decode(encodeLogEntry({
        'tags': {'a', 'b'}
      }));

      expect(decoded['tags'], ['a', 'b']);
    });

    test('leaves the entry it was given untouched', () {
      final at = DateTime(2026);
      final entry = <String, dynamic>{'at': at};

      encodeLogEntry(entry);

      expect(entry['at'], same(at));
    });
  });

  group('Built-in outputs survive values jsonEncode refuses', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('structured_log_'));
    tearDown(() => dir.deleteSync(recursive: true));

    final awkward = <String, dynamic>{
      'event': 'payment_failed',
      'at': DateTime.utc(2026, 10, 2),
      'cause': StateError('x'),
    };

    void expectAwkwardLine(String line) {
      final decoded = _decode(line);
      expect(decoded['event'], 'payment_failed');
      expect(decoded['at'], '2026-10-02T00:00:00.000Z');
      expect(decoded['cause'], 'Bad state: x');
    }

    test('defaultOutput', () {
      final printed = _capturePrints(
        () => defaultOutput(awkward, LogLevel.error),
      );
      expectAwkwardLine(printed.single);
    });

    test('coloredConsoleOutput', () {
      final printed = _capturePrints(
        () => coloredConsoleOutput(awkward, LogLevel.error),
      );
      expect(printed.single, contains('"at":"2026-10-02T00:00:00.000Z"'));
      expect(printed.single, contains('"cause":"Bad state: x"'));
    });

    test('fileOutput', () {
      final path = '${dir.path}/app.log';
      fileOutput(path)(awkward, LogLevel.error);
      expectAwkwardLine(File(path).readAsLinesSync().single);
    });

    test('rotatingFileOutput', () {
      final path = '${dir.path}/app.log';
      rotatingFileOutput(path)(awkward, LogLevel.error);
      expectAwkwardLine(File(path).readAsLinesSync().single);
    });

    test('AsyncFileOutput', () async {
      final path = '${dir.path}/app.log';
      final output = AsyncFileOutput(path)..call(awkward, LogLevel.error);
      await output.flushed;
      expectAwkwardLine(File(path).readAsLinesSync().single);
    });

    test('AsyncRotatingFileOutput', () async {
      final path = '${dir.path}/app.log';
      final output = AsyncRotatingFileOutput(path)
        ..call(awkward, LogLevel.error);
      await output.flushed;
      expectAwkwardLine(File(path).readAsLinesSync().single);
    });

    test('a logger writing to a file keeps the entry', () {
      final path = '${dir.path}/app.log';
      StructlogConfiguration.configure(output: fileOutput(path));

      getLogger().error('payment_failed', context: {
        'at': DateTime.utc(2026, 10, 2),
        'cause': StateError('x'),
      });

      expectAwkwardLine(File(path).readAsLinesSync().single);
    });
  });

  group('A failing processor', () {
    late List<Map<String, dynamic>> delivered;

    void configureWith(List<Processor> processors, {Set<String>? categories}) {
      delivered = [];
      StructlogConfiguration.configure(processors: processors, sinks: [
        LogSink(
          name: 'capture',
          output: (entry, level) => delivered.add(entry),
          categories: categories,
        ),
      ]);
    }

    Map<String, dynamic>? throwBeforeRedacting(Map<String, dynamic> entry) =>
        throw StateError('broken processor');

    test('does not reach the call site', () {
      configureWith([throwBeforeRedacting]);

      expect(
        () => _withStderr(_RecordingStdout(), () => getLogger().info('x')),
        returnsNormally,
      );
    });

    test('delivers a stub, never the unprocessed entry', () {
      configureWith([throwBeforeRedacting, redactKeys()]);

      _withStderr(
        _RecordingStdout(),
        () => getLogger('payments').info('login', context: {
          'category': 'auth',
          'password': 'hunter2',
        }),
      );

      final stub = delivered.single;
      expect(stub.keys.toSet(), {
        'event',
        'level',
        'timestamp',
        'logger',
        'category',
        'processor_failed',
      });
      expect(stub['event'], 'login');
      expect(stub['level'], 'info');
      expect(stub['logger'], 'payments');
      expect(stub['category'], 'auth');
      expect(stub['processor_failed'], 'StateError');
      expect(jsonEncode(stub), isNot(contains('hunter2')));
      expect(jsonEncode(stub), isNot(contains('broken processor')));
    });

    test('stops the processors after it', () {
      var laterRan = false;
      configureWith([
        throwBeforeRedacting,
        (entry) {
          laterRan = true;
          return entry;
        },
      ]);

      _withStderr(_RecordingStdout(), () => getLogger().info('x'));

      expect(laterRan, isFalse);
    });

    test('a stack overflow is contained too', () {
      Map<String, dynamic>? recurse(Map<String, dynamic> entry) =>
          recurse(entry);
      configureWith([recurse]);

      expect(
        () => _withStderr(_RecordingStdout(), () => getLogger().info('x')),
        returnsNormally,
      );
      expect(delivered.single['processor_failed'], 'StackOverflowError');
    });

    test("the stub is routed by the entry's category like any entry", () {
      configureWith([throwBeforeRedacting], categories: {'db'});

      _withStderr(_RecordingStdout(), () {
        getLogger().info('a', context: {'category': 'http'});
        getLogger().info('b', context: {'category': 'db'});
      });

      expect(delivered.map((e) => e['event']), ['b']);
    });

    test('is reported, with the stack, to stderr', () {
      configureWith([throwBeforeRedacting]);
      final stderr = _RecordingStdout();

      _withStderr(stderr, () => getLogger().info('x'));

      final report = stderr.lines.single;
      expect(report, startsWith('structured_log: '));
      expect(report, contains('StateError'));
      expect(report, contains('reliability_test.dart'));
    });
  });

  group('The logging call never throws', () {
    test('on a category that is not a string', () {
      final delivered = <Map<String, dynamic>>[];
      StructlogConfiguration.configure(output: (e, l) => delivered.add(e));

      expect(
        () => getLogger().info('x', context: {'category': 42}),
        returnsNormally,
      );
      expect(delivered.single['category'], 42);
    });

    test("on a sink whose accepts() throws, and the others still deliver", () {
      final delivered = <Map<String, dynamic>>[];
      StructlogConfiguration.configure(sinks: [
        _ThrowingAcceptsSink(),
        LogSink(name: 'good', output: (e, l) => delivered.add(e)),
      ]);

      expect(
        () => _withStderr(_RecordingStdout(), () => getLogger().info('x')),
        returnsNormally,
      );
      expect(delivered, hasLength(1));
    });

    test('on an entry a processor returned that cannot even be read', () {
      StructlogConfiguration.configure(
        processors: [(entry) => _UnreadableMap()],
        output: (e, l) {},
      );
      final stderr = _RecordingStdout();

      expect(
        () => _withStderr(stderr, () => getLogger().info('x')),
        returnsNormally,
      );
      expect(stderr.lines.single, startsWith('structured_log: logging "x"'));
    });

    test('when reporting a broken sink fails as well', () {
      StructlogConfiguration.configure(
        output: (e, l) => throw StateError('sink'),
      );

      expect(
        () => _withStderr(_ThrowingStdout(), () => getLogger().info('x')),
        returnsNormally,
      );
    });

    test('when reporting a broken processor fails as well', () {
      StructlogConfiguration.configure(
        processors: [(e) => throw StateError('processor')],
        output: (e, l) {},
      );

      expect(
        () => _withStderr(_ThrowingStdout(), () => getLogger().info('x')),
        returnsNormally,
      );
    });
  });

  group('redactKeys on values that are not maps or lists', () {
    test('looks inside toJson() and redacts what it finds', () {
      final result = redactKeys()({
        'event': 'e',
        'account': _Account('alice', 'hunter2'),
      })!;

      expect(result['account'], {'name': 'alice', 'password': '***'});
      expect(encodeLogEntry(result), isNot(contains('hunter2')));
    });

    test('keeps the object when toJson() holds nothing to redact', () {
      final user = _User('alice', DateTime.utc(2026));
      final entry = <String, dynamic>{'event': 'e', 'user': user};

      expect(redactKeys()(entry), same(entry));
    });

    test('walks a Set like a list', () {
      final result = redactKeys()({
        'event': 'e',
        'users': {
          {'password': 'x'},
        },
      })!;

      expect(result['users'], [
        {'password': '***'},
      ]);
    });

    test('a toJson() that returns its own object again is a cycle', () {
      final result = redactKeys()({'event': 'e', 'node': _SelfJson()})!;

      expect(result['node'], {'self': '<cycle>', 'token': '***'});
    });

    test('a toJson() that returns a plain value has nothing to walk', () {
      final value = _Version();
      final entry = <String, dynamic>{'event': 'e', 'password_hint': value};

      expect(redactKeys()(entry), same(entry));
      expect(_decode(encodeLogEntry(entry))['password_hint'], '1.2.3');
    });

    test('a toJson() that throws leaves the value to the encoder', () {
      final value = _ThrowingToJson();
      final entry = <String, dynamic>{'event': 'e', 'v': value};

      expect(redactKeys()(entry), same(entry));
    });
  });

  group('redactKeys on a cyclic entry', () {
    test('redacts what it can and marks the cycle', () {
      final m = <String, dynamic>{'token': 't'};
      m['self'] = m;

      final result = redactKeys()({'event': 'e', 'm': m})!;

      expect(result['m']['token'], '***');
      expect(result['m']['self'], '<cycle>');
      expect(m['token'], 't', reason: "the caller's map is left alone");
      expect(m['self'], same(m));
    });

    test('a cycle with nothing to redact does not throw', () {
      final list = <Object?>[];
      list.add(list);

      final result = redactKeys()({'event': 'e', 'list': list})!;

      expect(result['list'], ['<cycle>']);
    });

    test('a map reached twice without a cycle is not one', () {
      final shared = <String, dynamic>{'a': 1};
      final entry = <String, dynamic>{'x': shared, 'y': shared};

      expect(redactKeys()(entry), same(entry));
    });
  });

  group('Timestamps', () {
    Map<String, dynamic> logOne() {
      final delivered = <Map<String, dynamic>>[];
      StructlogConfiguration.configure(output: (e, l) => delivered.add(e));
      getLogger().info('x');
      return delivered.single;
    }

    test('are UTC by default', () {
      final timestamp = logOne()['timestamp'] as String;

      expect(timestamp, endsWith('Z'));
      expect(DateTime.parse(timestamp).isUtc, isTrue);
    });

    test('carry their offset in local mode', () {
      StructlogConfiguration.configure(
        timestampMode: TimestampMode.localWithOffset,
      );
      final before = DateTime.now();

      final timestamp = logOne()['timestamp'] as String;

      expect(timestamp, matches(RegExp(r'[+-]\d\d:\d\d$')));
      expect(timestamp, endsWith(formatOffset(before.timeZoneOffset)));
      expect(
        DateTime.parse(timestamp).difference(before).inSeconds.abs(),
        lessThan(5),
        reason: 'the offset makes it the same instant, read anywhere',
      );
    });

    test('a local time reads back as the same instant', () {
      final local = DateTime(2026, 10, 2, 12, 30, 15, 250);

      final formatted = formatTimestamp(local, TimestampMode.localWithOffset);

      expect(DateTime.parse(formatted).isAtSameMomentAs(local), isTrue);
      expect(
        formatTimestamp(local, TimestampMode.utc),
        local.toUtc().toIso8601String(),
      );
    });

    test('offsets are written sign, hours and minutes', () {
      expect(formatOffset(Duration.zero), '+00:00');
      expect(formatOffset(const Duration(hours: 3)), '+03:00');
      expect(formatOffset(const Duration(hours: 5, minutes: 45)), '+05:45');
      expect(formatOffset(const Duration(hours: -3, minutes: -30)), '-03:30');
    });

    test('configure keeps the mode when it is not given again', () {
      StructlogConfiguration.configure(
        timestampMode: TimestampMode.localWithOffset,
      );
      StructlogConfiguration.configure(initialContext: {'app': 'a'});

      expect(
        StructlogConfiguration.current.timestampMode,
        TimestampMode.localWithOffset,
      );
    });
  });

  group('Internal reports', () {
    test('a broken sink is reported to stderr', () {
      StructlogConfiguration.configure(sinks: [
        LogSink(name: 'bad', output: (e, l) => throw StateError('boom')),
      ]);
      final stderr = _RecordingStdout();

      _withStderr(stderr, () => getLogger().info('x'));

      expect(stderr.lines.single, startsWith('structured_log: sink "bad"'));
    });

    test('a failed async write is reported to stderr', () async {
      final dir = Directory.systemTemp.createTempSync('structured_log_');
      addTearDown(() => dir.deleteSync(recursive: true));
      Directory('${dir.path}/not_a_file').createSync();
      final stderr = _RecordingStdout();

      await IOOverrides.runZoned(
        () async {
          final output = AsyncFileOutput('${dir.path}/not_a_file')
            ..call({'event': 'x'}, LogLevel.info);
          await output.flushed;
        },
        stderr: () => stderr,
      );

      expect(stderr.lines.single, contains('async file output'));
    });

    test('without dart:io they go through print', () {
      final printed = _capturePrints(() => platformReport('message'));

      expect(printed, ['message']);
    });
  });
}

/// Runs [body] with `stderr` replaced by [stderr].
void _withStderr(Stdout stderr, void Function() body) =>
    IOOverrides.runZoned(body, stderr: () => stderr);

class _RecordingStdout implements Stdout {
  final lines = <String>[];

  @override
  void writeln([Object? object = '']) => lines.add('$object');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ThrowingAcceptsSink extends LogSink {
  _ThrowingAcceptsSink() : super(name: 'bad', output: (e, l) {});

  @override
  bool accepts(LogLevel level, String? category) => throw StateError('no');
}

/// A map whose every read throws — the worst a processor can hand back.
class _UnreadableMap implements Map<String, dynamic> {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('unread');
}

/// What `stderr` amounts to on the web: every write throws.
class _ThrowingStdout implements Stdout {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('stderr is not available');
}

Map<String, dynamic> _decode(String json) =>
    jsonDecode(json) as Map<String, dynamic>;

class _User {
  _User(this.name, this.joined);

  final String name;
  final DateTime joined;

  Map<String, Object?> toJson() => {'name': name, 'joined': joined};
}

class _Account {
  _Account(this.name, this.password);

  final String name;
  final String password;

  Map<String, Object?> toJson() => {'name': name, 'password': password};

  @override
  String toString() => 'Account(name: $name, password: $password)';
}

class _Version {
  String toJson() => '1.2.3';
}

class _SelfJson {
  Map<String, Object?> toJson() => {'self': this, 'token': 't'};
}

class _ThrowingToJson {
  Object? toJson() => throw StateError('no');

  @override
  String toString() => 'throwing toJson';
}

class _ThrowingToString {
  @override
  String toString() => throw StateError('no');
}

/// Runs [body] and returns whatever it printed.
List<String> _capturePrints(void Function() body) {
  final printed = <String>[];
  runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) => printed.add(line),
    ),
  );
  return printed;
}
