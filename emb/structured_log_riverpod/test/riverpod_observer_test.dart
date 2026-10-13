import 'dart:async';
import 'dart:convert';

import 'package:riverpod/legacy.dart';
import 'package:riverpod/misc.dart' show ProviderException;
import 'package:riverpod/riverpod.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_riverpod/structured_log_riverpod.dart';
import 'package:test/test.dart';

final counterProvider = StateProvider<int>((ref) => 0, name: 'counter');

final unnamedProvider = Provider<int>((ref) => 1);

final userProvider = Provider.family<String, String>(
  (ref, id) => 'user $id',
  name: 'user',
);

final unnamedFamily = Provider.family<String, int>((ref, id) => 'x$id');

final failingFuture = FutureProvider<int>(
  (ref) async => throw StateError('offline'),
  name: 'failingFuture',
);

final failingSync = Provider<int>(
  (ref) => throw StateError('boom'),
  name: 'failingSync',
);

final autoProvider = Provider.autoDispose<int>((ref) => 7, name: 'auto');

final baseProvider = StateProvider<int>((ref) => 1, name: 'base');

final derivedProvider = Provider<int>(
  (ref) => ref.watch(baseProvider) * 2,
  name: 'derived',
);

final longProvider = Provider<String>((ref) => 'x' * 5000, name: 'long');

class Session {
  @override
  String toString() => 'token=abc';
}

final sessionProvider = Provider<Session>((ref) => Session(), name: 'session');

class Unprintable {
  @override
  String toString() => throw UnsupportedError('no');
}

final unprintableProvider = Provider<Unprintable>(
  (ref) => Unprintable(),
  name: 'unprintable',
);

/// Records whether this Riverpod calls `didUnmountProvider` — it does from
/// 3.3.2, and not on 3.0.0–3.2.1 — so that the one test that depends on it
/// asks the installed version instead of guessing from a number.
final class _UnmountProbe extends ProviderObserver {
  bool called = false;

  @override
  void didUnmountProvider(ProviderObserverContext context) => called = true;
}

bool riverpodReportsUnmount() {
  final probe = _UnmountProbe();
  final container = ProviderContainer(observers: [probe]);
  container.read(unnamedProvider);
  container.dispose();
  return probe.called;
}

/// Collects every entry the sinks receive, at whatever level.
List<Map<String, dynamic>> captureEntries() {
  final entries = <Map<String, dynamic>>[];
  StructlogConfiguration.configure(
    sinks: [
      LogSink(
        name: 'capture',
        output: (entry, level) => entries.add(Map.of(entry)),
        minLevel: LogLevel.trace,
      ),
    ],
  );
  return entries;
}

/// Runs [body] in a zone that records uncaught errors and returns them:
/// Riverpod hands an exception from an observer to the zone's handler, so a
/// hook that throws would show up here instead of failing the test outright.
Future<List<Object>> uncaughtErrorsOf(Future<void> Function() body) async {
  final errors = <Object>[];
  final done = Completer<void>();
  runZonedGuarded(() async {
    await body();
    done.complete();
  }, (error, _) => errors.add(error));
  await done.future;
  return errors;
}

List<String> eventsOf(List<Map<String, dynamic>> entries) => [
  for (final entry in entries) entry['event'] as String,
];

Iterable<Map<String, dynamic>> entriesFor(
  List<Map<String, dynamic>> entries,
  String provider,
) => entries.where((entry) => entry['provider'] == provider);

ProviderContainer containerWith(StructuredLogRiverpodObserver observer) {
  final container = ProviderContainer(observers: [observer]);
  addTearDown(container.dispose);
  return container;
}

void main() {
  late List<Map<String, dynamic>> entries;
  final reportsUnmount = riverpodReportsUnmount();

  setUp(() {
    entries = captureEntries();
  });

  tearDown(StructlogConfiguration.reset);

  group('lifecycle', () {
    test('a named provider is added, then updated', () {
      final container = containerWith(StructuredLogRiverpodObserver());

      container.read(counterProvider);
      container.read(counterProvider.notifier).state = 1;

      expect(eventsOf(entries), ['provider_added', 'provider_updated']);
      expect(entries[0], containsPair('provider', 'counter'));
      expect(entries[0], containsPair('value', '0'));
      expect(entries[0], containsPair('value_type', 'int'));
      expect(entries[1], containsPair('provider', 'counter'));
      expect(entries[1], containsPair('previous_value', '0'));
      expect(entries[1], containsPair('value', '1'));
      expect(entries[1], containsPair('level', 'debug'));
    });

    test('tags every entry with category and logger', () {
      final container = containerWith(StructuredLogRiverpodObserver());

      container.read(counterProvider);

      expect(entries.single, containsPair('category', 'riverpod'));
      expect(entries.single, containsPair('logger', 'riverpod'));
    });

    test('an unnamed provider is told apart by its type, not toString()', () {
      final container = containerWith(StructuredLogRiverpodObserver());

      container.read(unnamedProvider);

      expect(entries.single, containsPair('provider', 'Provider<int>'));
    });

    test('a removed provider is logged as disposed', () async {
      final container = containerWith(StructuredLogRiverpodObserver());

      container.listen(autoProvider, (_, _) {}).close();
      await container.pump();

      expect(eventsOf(entriesFor(entries, 'auto').toList()), [
        'provider_added',
        'provider_disposed',
      ]);
    }, skip: reportsUnmount ? null : 'this riverpod has no didUnmountProvider');

    test('a rebuilt provider is not a disposed one', () async {
      final container = containerWith(StructuredLogRiverpodObserver());

      container.read(derivedProvider);
      container.read(baseProvider.notifier).state = 5;
      container.read(derivedProvider);
      container.refresh(derivedProvider);
      container.invalidate(derivedProvider);
      container.read(derivedProvider);
      await container.pump();

      expect(eventsOf(entries), isNot(contains('provider_disposed')));
      expect(
        entriesFor(
          entries,
          'derived',
        ).where((entry) => entry['event'] == 'provider_updated'),
        isNotEmpty,
      );
    });

    test('without didUnmountProvider the other entries are still written', () {
      final container = containerWith(StructuredLogRiverpodObserver());

      container.read(counterProvider);
      container.dispose();

      expect(eventsOf(entries), ['provider_added']);
    }, skip: reportsUnmount ? 'this riverpod has didUnmountProvider' : null);
  });

  group('family', () {
    test('the argument is a field of its own', () {
      final container = containerWith(StructuredLogRiverpodObserver());

      container.read(userProvider('42'));

      expect(entries.single, containsPair('provider', 'user'));
      expect(entries.single, containsPair('provider_argument', '42'));
      expect(entries.single, containsPair('value', 'user 42'));
    });

    test('an unnamed family is told apart by type, argument kept', () {
      final container = containerWith(StructuredLogRiverpodObserver());

      container.read(unnamedFamily(5));

      expect(entries.single, containsPair('provider', 'Provider<String>'));
      expect(entries.single, containsPair('provider_argument', '5'));
    });

    test('a provider without an argument has no provider_argument', () {
      final container = containerWith(StructuredLogRiverpodObserver());

      container.read(counterProvider);

      expect(entries.single, isNot(contains('provider_argument')));
    });

    test('describe withholds the argument too', () {
      final container = containerWith(
        StructuredLogRiverpodObserver(describe: (value) => null),
      );

      container.read(userProvider('hunter2'));

      expect(entries.single, isNot(contains('provider_argument')));
      expect(jsonEncode(entries), isNot(contains('hunter2')));
    });
  });

  group('values', () {
    test('a long value is cut to 1000 characters and an ellipsis', () {
      final container = containerWith(StructuredLogRiverpodObserver());

      container.read(longProvider);

      final value = entries.single['value'] as String;
      expect(value.length, 1001);
      expect(value, endsWith('…'));
      expect(value.substring(0, 1000), 'x' * 1000);
    });

    test('a toString() that throws leaves a placeholder naming the type', () {
      final container = containerWith(StructuredLogRiverpodObserver());

      container.read(unprintableProvider);

      expect(
        entries.single['value'],
        '<Unprintable.toString() threw UnsupportedError>',
      );
    });

    test('describe returning null drops the value and keeps the type', () {
      final container = containerWith(
        StructuredLogRiverpodObserver(
          describe: (value) => value is Session ? null : value.toString(),
        ),
      );

      container.read(sessionProvider);

      expect(entries.single, containsPair('value_type', 'Session'));
      expect(entries.single, isNot(contains('value')));
      expect(jsonEncode(entries), isNot(contains('token=abc')));
    });

    test('describe replaces the description of every value', () {
      final container = containerWith(
        StructuredLogRiverpodObserver(describe: (value) => 'V($value)'),
      );

      container.read(counterProvider);
      container.read(counterProvider.notifier).state = 2;

      expect(entries[1], containsPair('previous_value', 'V(0)'));
      expect(entries[1], containsPair('value', 'V(2)'));
    });
  });

  group('failures', () {
    test('a failing future is logged once, as provider_failed', () async {
      final container = containerWith(StructuredLogRiverpodObserver());

      container.listen(failingFuture, (_, _) {}, onError: (_, _) {});
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final failed = entries.where((e) => e['event'] == 'provider_failed');
      expect(failed, hasLength(1));
      expect(failed.single, containsPair('provider', 'failingFuture'));
      expect(failed.single, containsPair('level', 'error'));
      expect(failed.single, containsPair('error_type', 'StateError'));
      expect(failed.single['error'], contains('offline'));
      expect(failed.single['stack_trace'], isA<String>());
      final updates = entriesFor(
        entries,
        'failingFuture',
      ).where((e) => e['event'] == 'provider_updated');
      expect(updates, isEmpty);
    });

    test('a provider that throws while building is logged as failed', () {
      final container = containerWith(StructuredLogRiverpodObserver());

      expect(
        () => container.read(failingSync),
        throwsA(isA<ProviderException>()),
      );

      expect(eventsOf(entries), ['provider_added', 'provider_failed']);
      expect(entries[0], containsPair('value_type', 'Null'));
      expect(entries[1], containsPair('level', 'error'));
      expect(entries[1], containsPair('error_type', 'StateError'));
    });
  });

  group('levels', () {
    test('a hook set to null is off, the others stay', () {
      final container = containerWith(
        StructuredLogRiverpodObserver(
          levels: const RiverpodLogLevels(updated: null),
        ),
      );

      container.read(counterProvider);
      container.read(counterProvider.notifier).state = 1;

      expect(eventsOf(entries), ['provider_added']);
    });

    test('each hook logs at its own level', () {
      final container = containerWith(
        StructuredLogRiverpodObserver(
          levels: const RiverpodLogLevels(
            added: LogLevel.info,
            updated: LogLevel.warning,
            failed: LogLevel.critical,
          ),
        ),
      );

      container.read(counterProvider);
      container.read(counterProvider.notifier).state = 1;
      expect(
        () => container.read(failingSync),
        throwsA(isA<ProviderException>()),
      );

      expect(entries[0], containsPair('level', 'info'));
      expect(entries[1], containsPair('level', 'warning'));
      expect(entries.last, containsPair('level', 'critical'));
    });
  });

  group('filter', () {
    test('a rejected provider leaves no entries, the others stay', () {
      final container = containerWith(
        StructuredLogRiverpodObserver(
          filter: (provider) => provider.name != 'counter',
        ),
      );

      container.read(counterProvider);
      container.read(counterProvider.notifier).state = 1;
      container.read(userProvider('1'));

      expect(entriesFor(entries, 'counter'), isEmpty);
      expect(entriesFor(entries, 'user'), hasLength(1));
    });

    test(
      'a filter that throws costs the entry, not the state change',
      () async {
        late ProviderContainer container;
        final errors = await uncaughtErrorsOf(() async {
          container = containerWith(
            StructuredLogRiverpodObserver(
              filter: (provider) => throw const FormatException('secret=1'),
            ),
          );
          container.read(counterProvider);
          container.read(counterProvider.notifier).state = 1;
        });

        expect(errors, isEmpty);
        expect(entries, isEmpty);
        expect(container.read(counterProvider), 1);
      },
    );
  });

  group('never throws into Riverpod', () {
    test('a describe that throws leaves describe_failed and no text', () async {
      final errors = await uncaughtErrorsOf(() async {
        final container = containerWith(
          StructuredLogRiverpodObserver(
            describe: (value) => throw StateError('token=abc'),
          ),
        );
        container.read(counterProvider);
      });

      expect(errors, isEmpty);
      expect(entries.single, containsPair('describe_failed', 'StateError'));
      expect(entries.single, containsPair('provider', 'counter'));
      expect(jsonEncode(entries), isNot(contains('token=abc')));
    });

    test('a sink that throws does not reach the provider', () async {
      StructlogConfiguration.configure(
        sinks: [
          LogSink(
            name: 'broken',
            output: (entry, level) => throw StateError('disk full'),
            minLevel: LogLevel.trace,
          ),
        ],
      );
      late ProviderContainer container;
      final errors = await uncaughtErrorsOf(() async {
        container = containerWith(StructuredLogRiverpodObserver());
        container.read(counterProvider);
        container.read(counterProvider.notifier).state = 1;
      });

      expect(errors, isEmpty);
      expect(container.read(counterProvider), 1);
    });
  });

  group('configuration', () {
    test('a later configure() reaches an observer made before it', () {
      final container = containerWith(StructuredLogRiverpodObserver());
      final later = <Map<String, dynamic>>[];
      StructlogConfiguration.configure(
        sinks: [
          LogSink(
            name: 'later',
            output: (entry, level) => later.add(Map.of(entry)),
            minLevel: LogLevel.trace,
          ),
        ],
      );

      container.read(counterProvider);

      expect(eventsOf(later), ['provider_added']);
      expect(entries, isEmpty);
    });

    test('a given logger name and category replace the defaults', () {
      final container = containerWith(
        StructuredLogRiverpodObserver(loggerName: 'state', category: 'app'),
      );

      container.read(counterProvider);

      expect(entries.single, containsPair('logger', 'state'));
      expect(entries.single, containsPair('category', 'app'));
    });

    test('a null category binds none', () {
      final container = containerWith(
        StructuredLogRiverpodObserver(category: null),
      );

      container.read(counterProvider);

      expect(entries.single, isNot(contains('category')));
    });

    test('a given logger is used instead of getLogger()', () {
      final container = containerWith(
        StructuredLogRiverpodObserver(
          logger: getLogger('mine').bind({'app': 'demo'}),
        ),
      );

      container.read(counterProvider);

      expect(entries.single, containsPair('logger', 'mine'));
      expect(entries.single, containsPair('app', 'demo'));
    });

    test('nothing is described when no sink takes the level', () {
      var described = 0;
      StructlogConfiguration.configure(
        sinks: [
          LogSink(
            name: 'quiet',
            output: (entry, level) => entries.add(Map.of(entry)),
            minLevel: LogLevel.error,
          ),
        ],
      );
      final container = containerWith(
        StructuredLogRiverpodObserver(
          describe: (value) {
            described++;
            return value.toString();
          },
        ),
      );

      container.read(counterProvider);
      container.read(counterProvider.notifier).state = 1;

      expect(described, 0);
      expect(entries, isEmpty);
    });
  });
}
