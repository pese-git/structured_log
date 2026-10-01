import 'package:cherrypick/cherrypick.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_cherrypick/structured_log_cherrypick.dart';

class ApiClient {}

class Repository {
  Repository(ApiClient _);
}

class AppModule extends Module {
  @override
  void builder(Scope currentScope) {
    bind<ApiClient>().toProvide(() => ApiClient()).singleton();
  }
}

class FeatureModule extends Module {
  @override
  void builder(Scope currentScope) {
    bind<Repository>().toProvide(
      () => Repository(currentScope.resolve<ApiClient>()),
    );
  }
}

/// A root scope, a feature scope opened and closed under it, and a resolve
/// of a binding nobody registered — each leaves an entry on the console.
Future<void> main() async {
  StructlogConfiguration.configure(
    sinks: [LogSink(name: 'console', output: coloredConsoleOutput)],
  );
  // Before the first scope: a scope takes the global observer when it is
  // created.
  CherryPick.setGlobalObserver(StructuredLogCherryPickObserver());

  final root = CherryPick.openRootScope()..installModules([AppModule()]);
  root.openSubScope('feature')
    ..installModules([FeatureModule()])
    ..resolve<Repository>();
  await root.closeSubScope('feature');

  try {
    root.resolve<Repository>(); // bound only in the closed feature scope
  } on StateError {
    // Logged as di.error; nothing else to do here.
  }

  await CherryPick.closeRootScope();
}
