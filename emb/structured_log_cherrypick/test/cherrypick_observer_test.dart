import 'dart:convert';

import 'package:cherrypick/cherrypick.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_cherrypick/structured_log_cherrypick.dart';
import 'package:test/test.dart';

List<Map<String, dynamic>> captureEntries({List<Processor>? processors}) {
  final entries = <Map<String, dynamic>>[];
  StructlogConfiguration.configure(
    processors: processors,
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

List<String> eventsOf(List<Map<String, dynamic>> entries) =>
    [for (final entry in entries) entry['event'] as String];

/// Something a container really holds and that must never be printed.
class TokenStore {
  @override
  String toString() => 'TokenStore(refresh=secret-refresh-token)';
}

class AppModule extends Module {
  @override
  void builder(Scope currentScope) {
    bind<TokenStore>().toProvide(() => TokenStore()).singleton();
  }
}

class A {
  A(B _);
}

class B {
  B(A _);
}

class CycleModule extends Module {
  @override
  void builder(Scope currentScope) {
    bind<A>().toProvide(() => A(currentScope.resolve<B>()));
    bind<B>().toProvide(() => B(currentScope.resolve<A>()));
  }
}

/// Every per-instance hook on, so the tests can see what they would say.
const verbose = DiLogLevels(
  bindingRegistered: LogLevel.trace,
  instanceRequested: LogLevel.trace,
  instanceCreated: LogLevel.trace,
  cacheHit: LogLevel.trace,
  cacheMiss: LogLevel.trace,
  diagnostic: LogLevel.trace,
);

void main() {
  late List<Map<String, dynamic>> entries;

  setUp(() => entries = captureEntries());

  tearDown(() async {
    await CherryPick.closeRootScope();
    CherryPick.disableGlobalCycleDetection();
    CherryPick.disableGlobalCrossScopeCycleDetection();
    CherryPick.setGlobalObserver(SilentCherryPickObserver());
    StructlogConfiguration.reset();
  });

  group('a container at work', () {
    test('reports scopes and modules, as the global observer', () async {
      CherryPick.setGlobalObserver(StructuredLogCherryPickObserver());
      final root = CherryPick.openRootScope();
      root.openSubScope('feature').installModules([AppModule()]);
      // The container reports a close only for a sub-scope closed through
      // its parent; closing the root scope says nothing.
      await root.closeSubScope('feature');

      // A scope is reported by the id the container gives it, not the name
      // it was opened under.
      final opened = [
        for (final e in entries)
          if (e['event'] == 'di.scope_opened') e['scope'],
      ];
      expect(opened, hasLength(2)); // the root, then the sub-scope
      final installed =
          entries.singleWhere((e) => e['event'] == 'di.modules_installed');
      expect(installed['modules'], ['AppModule']);
      final closed =
          entries.singleWhere((e) => e['event'] == 'di.scope_closed');
      expect(closed['scope'], opened.last);
      for (final entry in entries) {
        expect(entry, containsPair('category', 'di'));
        expect(entry, containsPair('logger', 'di'));
        expect(entry, containsPair('level', 'debug'));
      }
    });

    test('a scope given the observer directly reports to it', () {
      Scope(null, observer: StructuredLogCherryPickObserver())
          .installModules([AppModule()]);

      expect(eventsOf(entries), ['di.scope_opened', 'di.modules_installed']);
    });

    test('stays quiet about every resolve by default', () {
      final scope = Scope(null, observer: StructuredLogCherryPickObserver())
        ..installModules([AppModule()]);
      entries.clear();
      for (var i = 0; i < 5; i++) {
        scope.resolve<TokenStore>();
      }

      expect(entries, isEmpty);
    });

    test(
        'per-instance reports, once turned on, name the type, not the '
        'instance', () {
      final scope = Scope(
        null,
        observer: StructuredLogCherryPickObserver(levels: verbose),
      )..installModules([AppModule()]);
      scope
        ..resolve<TokenStore>()
        ..resolve<TokenStore>();

      final events = eventsOf(entries).toSet();
      expect(
        events,
        containsAll([
          'di.binding_registered',
          'di.instance_requested',
          'di.instance_created',
          'di.diagnostic',
        ]),
      );
      final created =
          entries.firstWhere((e) => e['event'] == 'di.instance_created');
      expect(created, containsPair('type', 'TokenStore'));
      expect(created, containsPair('level', 'trace'));
      expect(jsonEncode(entries), isNot(contains('secret-refresh-token')));
    });

    test('a cycle the container finds is an error with its chain', () {
      final scope = Scope(null, observer: StructuredLogCherryPickObserver())
        ..enableCycleDetection()
        ..installModules([CycleModule()]);

      expect(
        () => scope.resolve<A>(),
        throwsA(isA<CircularDependencyException>()),
      );
      final cycle =
          entries.firstWhere((e) => e['event'] == 'di.cycle_detected');
      expect(cycle, containsPair('level', 'error'));
      expect(cycle['chain'], containsAll(['A', 'B']));
    });

    test('a missing binding reaches the log as an error', () {
      final scope = Scope(null, observer: StructuredLogCherryPickObserver());

      expect(() => scope.resolve<TokenStore>(), throwsA(anything));
      final error = entries.firstWhere((e) => e['event'] == 'di.error');
      expect(error, containsPair('level', 'error'));
      expect(error['message'], contains('TokenStore'));
    });
  });

  group('each hook', () {
    late StructuredLogCherryPickObserver observer;

    setUp(() => observer = StructuredLogCherryPickObserver(levels: verbose));

    test('carries the scope when it has one, and leaves it out when not', () {
      observer
        ..onModulesInstalled(['M'], scopeName: 'app')
        ..onModulesRemoved(['M'])
        ..onScopeOpened('app')
        ..onScopeClosed('app');

      expect(entries[0], containsPair('scope', 'app'));
      expect(entries[1].keys, isNot(contains('scope')));
      expect(eventsOf(entries), [
        'di.modules_installed',
        'di.modules_removed',
        'di.scope_opened',
        'di.scope_closed',
      ]);
    });

    // The container (3.0 and 4.0-dev alike) declares these three hooks but
    // never calls them; they are driven directly so that the day it does,
    // what they say is already pinned.
    test('cache hits and misses name the binding', () {
      observer
        ..onCacheHit('tokens', TokenStore, scopeName: 'auth')
        ..onCacheMiss('tokens', TokenStore);

      expect(eventsOf(entries), ['di.cache_hit', 'di.cache_miss']);
      expect(entries.first, containsPair('scope', 'auth'));
      expect(entries.last, containsPair('type', 'TokenStore'));
    });

    test('disposal names the binding, never the instance', () {
      observer.onInstanceDisposed(
        'tokens',
        TokenStore,
        TokenStore(),
        scopeName: 'auth',
      );

      expect(entries.single, containsPair('event', 'di.instance_disposed'));
      expect(entries.single, containsPair('type', 'TokenStore'));
      expect(entries.single, containsPair('name', 'tokens'));
      expect(entries.single, containsPair('scope', 'auth'));
      expect(jsonEncode(entries), isNot(contains('secret-refresh-token')));
    });

    test('an error is logged by its type, with the stack if there is one', () {
      observer
        ..onError('could not resolve', StateError('secret detail'),
            StackTrace.current)
        ..onError('no error object', null, StackTrace.empty);

      final [withError, withoutError] = entries;
      expect(withError, containsPair('error', 'StateError'));
      expect(withError['stack_trace'], isNotEmpty);
      expect(withoutError.keys, isNot(contains('error')));
      expect(withoutError.keys, isNot(contains('stack_trace')));
      expect(jsonEncode(entries), isNot(contains('secret detail')));
    });

    test('a warning and a diagnostic keep their message, not their details',
        () {
      observer
        ..onWarning('binding overridden', details: TokenStore())
        ..onDiagnostic('Successfully resolved', details: TokenStore());

      expect(entries[0], containsPair('level', 'warning'));
      expect(entries[0], containsPair('message', 'binding overridden'));
      expect(entries[1], containsPair('event', 'di.diagnostic'));
      expect(jsonEncode(entries), isNot(contains('secret-refresh-token')));
    });

    test('every entry survives jsonEncode', () {
      observer
        ..onCycleDetected(['A', 'B', 'A'], scopeName: 'app')
        ..onBindingRegistered('n', TokenStore)
        ..onError('m', Exception('x'), StackTrace.current);

      expect(() => jsonEncode(entries), returnsNormally);
    });
  });

  group('configuration', () {
    test('a null level turns that hook off', () {
      StructuredLogCherryPickObserver(
        levels: const DiLogLevels(scopeOpened: null),
      )
        ..onScopeOpened('app')
        ..onScopeClosed('app');

      expect(eventsOf(entries), ['di.scope_closed']);
    });

    test('a given logger and category replace the defaults', () {
      StructuredLogCherryPickObserver(
        logger: getLogger('server').bind({'component': 'graph'}),
        category: 'wiring',
      ).onScopeOpened('app');

      expect(entries.single, containsPair('logger', 'server'));
      expect(entries.single, containsPair('component', 'graph'));
      expect(entries.single, containsPair('category', 'wiring'));
    });

    test('a null category keeps the one the logger carries', () {
      StructuredLogCherryPickObserver(
        logger: getLogger().bind({'category': 'mine'}),
        category: null,
      ).onScopeOpened('app');

      expect(entries.single, containsPair('category', 'mine'));
    });

    test('a later configure() reaches an observer built without a logger', () {
      final observer = StructuredLogCherryPickObserver();
      final later = captureEntries();
      observer.onScopeOpened('app');

      expect(entries, isEmpty);
      expect(eventsOf(later), ['di.scope_opened']);
    });
  });

  test('a logger that throws costs the entry, not the resolve', () {
    captureEntries(processors: [(_) => throw StateError('processor broke')]);
    final scope = Scope(null, observer: StructuredLogCherryPickObserver())
      ..installModules([AppModule()]);

    expect(scope.resolve<TokenStore>(), isA<TokenStore>());
  });
}
