import 'dart:async';
import 'dart:convert';

import 'package:bloc/bloc.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_bloc/structured_log_bloc.dart';
import 'package:test/test.dart';

class CounterCubit extends Cubit<int> {
  CounterCubit() : super(0);

  void increment() => emit(state + 1);
}

sealed class CounterEvent {}

class Incremented extends CounterEvent {
  @override
  String toString() => 'Incremented()';
}

class Failed extends CounterEvent {}

class CounterBloc extends Bloc<CounterEvent, int> {
  CounterBloc() : super(0) {
    on<Incremented>((event, emit) => emit(state + 1));
    on<Failed>((event, emit) => throw StateError('boom'));
  }
}

class Secret {
  @override
  String toString() => 'password=hunter2';
}

class Unprintable {
  @override
  String toString() => throw UnsupportedError('no');
}

class SecretCubit extends Cubit<Object> {
  SecretCubit(super.initial);

  void set(Object value) => emit(value);
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

/// Runs [body] in a zone that swallows uncaught errors and returns them:
/// `Bloc` rethrows a handler's exception after reporting it, and outside a
/// guarded zone that fails the test.
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

List<String> eventsOf(List<Map<String, dynamic>> entries) =>
    [for (final entry in entries) entry['event'] as String];

void main() {
  late BlocObserver previousObserver;
  late List<Map<String, dynamic>> entries;

  setUp(() {
    previousObserver = Bloc.observer;
    entries = captureEntries();
  });

  tearDown(() {
    Bloc.observer = previousObserver;
    StructlogConfiguration.reset();
  });

  group('cubit', () {
    test('logs creation, each change and closing', () async {
      Bloc.observer = StructuredLogBlocObserver();
      final cubit = CounterCubit()..increment();
      await cubit.close();

      expect(eventsOf(entries), ['bloc_created', 'bloc_change', 'bloc_closed']);
      expect(entries[0], containsPair('state', '0'));
      expect(entries[0], containsPair('state_type', 'int'));
      expect(entries[1], containsPair('current_state', '0'));
      expect(entries[1], containsPair('next_state', '1'));
      expect(entries[1], containsPair('level', 'debug'));
    });

    test('tags every entry with category, logger, type and instance', () {
      Bloc.observer = StructuredLogBlocObserver();
      final first = CounterCubit();
      final second = CounterCubit();

      for (final entry in entries) {
        expect(entry, containsPair('category', 'bloc'));
        expect(entry, containsPair('logger', 'bloc'));
        expect(entry, containsPair('bloc', 'CounterCubit'));
      }
      expect(entries[0]['bloc_instance'], identityHashCode(first));
      expect(entries[1]['bloc_instance'], identityHashCode(second));
      expect(entries[0]['bloc_instance'], isNot(entries[1]['bloc_instance']));
    });
  });

  group('bloc', () {
    test('logs the event and one transition per state change', () async {
      Bloc.observer = StructuredLogBlocObserver();
      final bloc = CounterBloc()..add(Incremented());
      await bloc.stream.first;

      // onChange fires for blocs too; logging it would repeat the transition.
      expect(eventsOf(entries), [
        'bloc_created',
        'bloc_event_added',
        'bloc_transition',
      ]);
      expect(entries[1], containsPair('bloc_event', 'Incremented()'));
      expect(entries[1], containsPair('bloc_event_type', 'Incremented'));
      expect(entries[2], containsPair('bloc_event', 'Incremented()'));
      expect(entries[2], containsPair('current_state', '0'));
      expect(entries[2], containsPair('next_state', '1'));
      expect(entries[2], containsPair('state_type', 'int'));

      await bloc.close();
      expect(eventsOf(entries).skip(3), ['bloc_event_done', 'bloc_closed']);
      expect(entries[3].containsKey('error'), isFalse);
    });

    test('logs a failing handler as an error and as a failed done', () async {
      Bloc.observer = StructuredLogBlocObserver();
      final uncaught = await uncaughtErrorsOf(() async {
        final bloc = CounterBloc()..add(Failed());
        await bloc.close();
      });
      expect(uncaught.single, isA<StateError>());

      final error = entries.singleWhere((e) => e['event'] == 'bloc_error');
      expect(error, containsPair('level', 'error'));
      expect(error, containsPair('error_type', 'StateError'));
      expect(error['error'], contains('boom'));
      expect(error['stack_trace'],
          isA<String>().having((s) => s, 'trace', isNotEmpty));

      final done = entries.singleWhere((e) => e['event'] == 'bloc_event_done');
      expect(done, containsPair('level', 'trace'));
      expect(done, containsPair('bloc_event_type', 'Failed'));
      expect(done, containsPair('error_type', 'StateError'));
      expect(done.containsKey('stack_trace'), isFalse);
    });

    test('logs addError on a cubit', () async {
      Bloc.observer = StructuredLogBlocObserver();
      final cubit = CounterCubit();
      // ignore: invalid_use_of_protected_member
      cubit.addError(const FormatException('bad'), StackTrace.current);
      await cubit.close();

      final error = entries.singleWhere((e) => e['event'] == 'bloc_error');
      expect(error, containsPair('error_type', 'FormatException'));
    });
  });

  group('configuration', () {
    test('a null level turns its hook off', () async {
      Bloc.observer = StructuredLogBlocObserver(
        levels: const BlocLogLevels(create: null, close: null, done: null),
      );
      final bloc = CounterBloc()..add(Incremented());
      await bloc.stream.first;
      await bloc.close();

      expect(eventsOf(entries), ['bloc_event_added', 'bloc_transition']);
    });

    test('levels are applied per hook', () {
      Bloc.observer = StructuredLogBlocObserver(
        levels: const BlocLogLevels(create: LogLevel.info),
      );
      CounterCubit();

      expect(entries.single, containsPair('level', 'info'));
    });

    test('filter keeps the blocs it rejects out of the log', () async {
      Bloc.observer = StructuredLogBlocObserver(
        filter: (bloc) => bloc is! CounterCubit,
      );
      CounterCubit().increment();
      CounterBloc();

      expect(entries.map((e) => e['bloc']).toSet(), {'CounterBloc'});
    });

    test('a given logger and category replace the defaults', () {
      final logger = getLogger('ui').bind({'screen': 'home'});
      Bloc.observer = StructuredLogBlocObserver(
        logger: logger,
        category: 'state',
      );
      CounterCubit();

      expect(entries.single, containsPair('logger', 'ui'));
      expect(entries.single, containsPair('screen', 'home'));
      expect(entries.single, containsPair('category', 'state'));
    });

    test('a null category keeps the one the logger carries', () {
      Bloc.observer = StructuredLogBlocObserver(
        logger: getLogger().bind({'category': 'mine'}),
        category: null,
      );
      CounterCubit();

      expect(entries.single, containsPair('category', 'mine'));
    });

    test('a later configure() reaches an observer built without a logger', () {
      Bloc.observer = StructuredLogBlocObserver();
      final later = captureEntries();
      CounterCubit();

      expect(entries, isEmpty);
      expect(eventsOf(later), ['bloc_created']);
    });
  });

  group('describe', () {
    test('withholding a value keeps its type', () {
      Bloc.observer = StructuredLogBlocObserver(
        describe: (value) => value is Secret ? null : describeBlocValue(value),
      );
      SecretCubit('public').set(Secret());

      final change = entries.singleWhere((e) => e['event'] == 'bloc_change');
      expect(change, containsPair('current_state', 'public'));
      expect(change.containsKey('next_state'), isFalse);
      expect(change, containsPair('state_type', 'Secret'));
      expect(jsonEncode(entries), isNot(contains('hunter2')));
    });

    test('a map it returns is redacted by redactKeys like any field', () {
      StructlogConfiguration.configure(processors: [redactKeys()]);
      Bloc.observer = StructuredLogBlocObserver(
        describe: (value) => value is Map ? value : describeBlocValue(value),
      );
      SecretCubit('signed out').set({'user': 'u', 'token': 'hunter2'});

      final change = entries.singleWhere((e) => e['event'] == 'bloc_change');
      expect(change['next_state'], {'user': 'u', 'token': '***'});
      expect(jsonEncode(entries), isNot(contains('hunter2')));
    });

    test('the default cuts long values short', () {
      final long = 'x' * (defaultBlocValueMaxLength + 50);
      final described = describeBlocValue(long) as String;

      expect(described.length, defaultBlocValueMaxLength + 1);
      expect(described, endsWith('…'));
      expect(describeBlocValue('short'), 'short');
      expect(describeBlocValue(null), isNull);
    });

    test('a throwing toString() becomes a placeholder', () {
      Bloc.observer = StructuredLogBlocObserver();
      SecretCubit(Unprintable());

      expect(
        entries.single['state'],
        '<Unprintable.toString() threw UnsupportedError>',
      );
    });

    test('a throwing describer costs the values, not the emit', () {
      Bloc.observer = StructuredLogBlocObserver(
        describe: (_) => throw StateError('describer broke'),
      );
      final cubit = CounterCubit()..increment();

      expect(cubit.state, 1);
      expect(eventsOf(entries), ['bloc_created', 'bloc_change']);
      expect(entries.last, containsPair('describe_failed', 'StateError'));
      expect(entries.last, containsPair('bloc', 'CounterCubit'));
    });

    test('every entry survives jsonEncode', () async {
      Bloc.observer = StructuredLogBlocObserver();
      await uncaughtErrorsOf(() async {
        final bloc = CounterBloc()
          ..add(Incremented())
          ..add(Failed());
        await bloc.close();
      });
      expect(eventsOf(entries), contains('bloc_error'));

      expect(() => jsonEncode(entries), returnsNormally);
    });
  });
}
