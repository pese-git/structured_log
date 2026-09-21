import 'package:cherrypick/cherrypick.dart';
import 'package:structured_log/structured_log.dart';

/// What the DI container reports, through the server's own logger — the third
/// journal, the one that must never be confused with the other two
/// (`design.md` decision 48).
///
/// Scopes coming and going, modules being installed, and disposals are debug
/// noise a person tracing the container wants, and they are how a wiring that
/// silently did not happen shows up: a scope that never opened, or never closed.
/// A cycle, a warning or an error is not noise: those are mistakes in the wiring,
/// and they go out at the levels that survive a production log level.
///
/// Every request for and creation of an instance is left out on purpose — the
/// container is asked a great many times at startup, each is cheap, and none says
/// anything a missing binding does not. Only *names* and *types* are logged,
/// never the instance: the graph holds the database and the token settings, and
/// an object printed is a secret printed (`test/logging/diagnostics_isolation_test`).
///
/// Implements the interface rather than extending `SilentCherryPickObserver`:
/// the container skips calling an observer that is one, which would silence this
/// too.
class StructuredLogCherryPickObserver implements CherryPickObserver {
  final BoundLogger _logger;

  StructuredLogCherryPickObserver(this._logger);

  @override
  void onScopeOpened(String name) =>
      _logger.debug('di.scope_opened', context: {'scope': name});

  @override
  void onScopeClosed(String name) =>
      _logger.debug('di.scope_closed', context: {'scope': name});

  @override
  void onModulesInstalled(List<String> moduleNames, {String? scopeName}) =>
      _logger.debug(
        'di.modules_installed',
        context: {'modules': moduleNames, 'scope': scopeName},
      );

  @override
  void onModulesRemoved(List<String> moduleNames, {String? scopeName}) =>
      _logger.debug(
        'di.modules_removed',
        context: {'modules': moduleNames, 'scope': scopeName},
      );

  @override
  void onInstanceDisposed(
    String name,
    Type type,
    Object instance, {
    String? scopeName,
  }) => _logger.debug(
    'di.instance_disposed',
    context: {'type': type.toString(), 'name': name, 'scope': scopeName},
  );

  @override
  void onCycleDetected(List<String> chain, {String? scopeName}) =>
      _logger.error(
        'di.cycle_detected',
        context: {'chain': chain, 'scope': scopeName},
      );

  @override
  void onWarning(String message, {Object? details}) =>
      _logger.warning('di.warning', context: {'message': message});

  @override
  void onError(String message, Object? error, StackTrace? stackTrace) =>
      _logger.error(
        'di.error',
        context: {'message': message, 'error': error.runtimeType.toString()},
      );

  // Says "Successfully resolved: X" for every resolve — the request noise the
  // class doc leaves out.
  @override
  void onDiagnostic(String message, {Object? details}) {}

  @override
  void onBindingRegistered(String name, Type type, {String? scopeName}) {}

  @override
  void onInstanceRequested(String name, Type type, {String? scopeName}) {}

  @override
  void onInstanceCreated(
    String name,
    Type type,
    Object instance, {
    String? scopeName,
  }) {}

  @override
  void onCacheHit(String name, Type type, {String? scopeName}) {}

  @override
  void onCacheMiss(String name, Type type, {String? scopeName}) {}
}

/// Sets up the container's global behaviour for a process: the observer, and
/// cycle detection in every scope, across scopes too.
///
/// Before the first scope is opened through the helper — a scope takes the
/// global observer when it is created. Cycle detection stays on in production: a
/// cycle is a mistake in the wiring, and the alternative to reporting it is a
/// stack overflow on startup.
///
/// Only scopes opened through `CherryPick` are reached; the isolated scopes tests
/// build for themselves are deliberately not.
void configureContainer(BoundLogger logger) {
  CherryPick.setGlobalObserver(StructuredLogCherryPickObserver(logger));
  CherryPick.enableGlobalCycleDetection();
  CherryPick.enableGlobalCrossScopeCycleDetection();
}
