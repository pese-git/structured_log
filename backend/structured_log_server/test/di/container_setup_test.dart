import 'package:cherrypick/cherrypick.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_server/src/di/container_setup.dart';
import 'package:test/test.dart';

/// What the container was heard saying, through a logger that writes here.
typedef _Heard = List<({Map<String, dynamic> entry, LogLevel level})>;

_Heard _capture() {
  final heard = <({Map<String, dynamic> entry, LogLevel level})>[];
  StructlogConfiguration.configure(
    sinks: [
      LogSink(
        name: 'capture',
        output: (entry, level) => heard.add((entry: entry, level: level)),
      ),
    ],
  );
  return heard;
}

class _A {
  _A(_B _);
}

class _B {
  _B(_A _);
}

class _CycleModule extends Module {
  @override
  void builder(Scope currentScope) {
    bind<_A>().toProvide(() => _A(currentScope.resolve<_B>()));
    bind<_B>().toProvide(() => _B(currentScope.resolve<_A>()));
  }
}

void main() {
  tearDown(() async {
    await CherryPick.closeRootScope();
    CherryPick.disableGlobalCycleDetection();
    CherryPick.disableGlobalCrossScopeCycleDetection();
    CherryPick.setGlobalObserver(SilentCherryPickObserver());
    StructlogConfiguration.reset();
  });

  group('the observer', () {
    late _Heard heard;
    late StructuredLogCherryPickObserver observer;

    setUp(() {
      heard = _capture();
      observer = StructuredLogCherryPickObserver(getLogger('test'));
    });

    test('says when a scope opens and closes, and what was installed', () {
      observer.onScopeOpened('server');
      observer.onModulesInstalled(['AppModule'], scopeName: 'server');
      observer.onScopeClosed('server');

      expect(heard.map((h) => h.entry['event']), [
        'di.scope_opened',
        'di.modules_installed',
        'di.scope_closed',
      ]);
      expect(heard[1].entry['modules'], ['AppModule']);
      expect(heard.every((h) => h.level == LogLevel.debug), isTrue);
    });

    test(
      'reports a cycle as an error, and errors and warnings above debug',
      () {
        observer.onCycleDetected(['A', 'B', 'A'], scopeName: 'server');
        observer.onWarning('a binding was overridden');
        observer.onError(
          'could not resolve',
          StateError('x'),
          StackTrace.empty,
        );

        expect(heard.map((h) => h.level), [
          LogLevel.error,
          LogLevel.warning,
          LogLevel.error,
        ]);
        expect(heard.first.entry['chain'], ['A', 'B', 'A']);
      },
    );

    test('hears a cycle from the container that found it', () {
      final scope = Scope(null, observer: observer)
        ..enableCycleDetection()
        ..installModules([_CycleModule()]);

      expect(
        () => scope.resolve<_A>(),
        throwsA(isA<CircularDependencyException>()),
      );
      expect(
        heard.any(
          (h) =>
              h.entry['event'] == 'di.cycle_detected' &&
              h.level == LogLevel.error,
        ),
        isTrue,
      );
    });

    test('never prints an instance, and stays quiet about requests', () {
      const secret = 'signing-secret-value';
      observer.onInstanceCreated('TokenSettings', String, secret);
      observer.onInstanceDisposed('TokenSettings', String, secret);
      observer.onInstanceRequested('TokenSettings', String);
      observer.onCacheHit('TokenSettings', String);
      observer.onDiagnostic('Successfully resolved: TokenSettings');

      expect(heard.map((h) => h.entry['event']), ['di.instance_disposed']);
      expect(heard.toString(), isNot(contains(secret)));
    });
  });

  group('configureContainer', () {
    test('turns cycle detection on, in a scope and across scopes', () {
      configureContainer(getLogger('test'));

      expect(CherryPick.isGlobalCycleDetectionEnabled, isTrue);
      expect(CherryPick.isGlobalCrossScopeCycleDetectionEnabled, isTrue);
    });

    test('a scope opened afterwards reports to the logger it was given', () {
      final heard = _capture();
      configureContainer(getLogger('test'));

      CherryPick.openScope(
        scopeName: 'server',
      ).installModules([_CycleModule()]);

      expect(
        heard.map((h) => h.entry['event']),
        containsAll(['di.scope_opened', 'di.modules_installed']),
      );
    });

    test('a cycle is reported instead of overflowing the stack', () {
      configureContainer(getLogger('test'));
      final scope = CherryPick.openScope(scopeName: 'server')
        ..installModules([_CycleModule()]);

      expect(
        () => scope.resolve<_A>(),
        throwsA(isA<CircularDependencyException>()),
      );
    });
  });
}
