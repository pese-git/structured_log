import 'package:cherrypick/cherrypick.dart';
import 'package:structured_log/structured_log.dart';

/// The level each [CherryPickObserver] hook logs at; `null` turns it off.
///
/// The defaults split the container's reports in two. What says how the
/// graph was put together and taken apart — scopes, modules, disposals — is
/// `debug`: a person tracing the container wants it, and it is how a wiring
/// that silently did not happen shows up (a scope that never opened, or
/// never closed). A cycle, a warning or an error is a mistake in the wiring
/// and goes out at a level that survives a production build.
///
/// Every per-instance report — registrations, requests, creations, cache
/// hits and misses, and the diagnostic that says "Successfully resolved"
/// for each of them — is off: the container is asked a great many times,
/// each is cheap, and none says anything a missing binding does not. Turn
/// one on (at `trace`, say) to watch resolution in detail.
class DiLogLevels {
  /// A scope was opened.
  final LogLevel? scopeOpened;

  /// A scope was closed.
  final LogLevel? scopeClosed;

  /// Modules were installed into a scope.
  final LogLevel? modulesInstalled;

  /// Modules were removed from a scope.
  final LogLevel? modulesRemoved;

  /// A binding was registered.
  final LogLevel? bindingRegistered;

  /// An instance was asked for.
  final LogLevel? instanceRequested;

  /// An instance was created.
  final LogLevel? instanceCreated;

  /// An instance was disposed.
  final LogLevel? instanceDisposed;

  /// A cached instance was handed out.
  final LogLevel? cacheHit;

  /// No cached instance was found.
  final LogLevel? cacheMiss;

  /// A dependency cycle was found.
  final LogLevel? cycleDetected;

  /// The container's free-form diagnostic messages.
  final LogLevel? diagnostic;

  /// The container warned about something.
  final LogLevel? warning;

  /// The container hit an error.
  final LogLevel? error;

  const DiLogLevels({
    this.scopeOpened = LogLevel.debug,
    this.scopeClosed = LogLevel.debug,
    this.modulesInstalled = LogLevel.debug,
    this.modulesRemoved = LogLevel.debug,
    this.bindingRegistered,
    this.instanceRequested,
    this.instanceCreated,
    this.instanceDisposed = LogLevel.debug,
    this.cacheHit,
    this.cacheMiss,
    this.cycleDetected = LogLevel.error,
    this.diagnostic,
    this.warning = LogLevel.warning,
    this.error = LogLevel.error,
  });
}

/// A [CherryPickObserver] that writes what the cherrypick container does
/// to `structured_log`.
///
/// Install it before the scopes it should hear are opened — a scope takes
/// the global observer when it is created:
///
/// ```dart
/// CherryPick.setGlobalObserver(StructuredLogCherryPickObserver());
/// final scope = CherryPick.openRootScope()..installModules([AppModule()]);
/// ```
///
/// Or hand it to one scope: `Scope(null, observer: observer)`.
///
/// Every entry carries `category` (`di` by default) and is named
/// `di.<what happened>`: `di.scope_opened`, `di.scope_closed`,
/// `di.modules_installed`, `di.modules_removed`, `di.instance_disposed`,
/// `di.cycle_detected`, `di.warning`, `di.error` — and, when turned on in
/// [levels], `di.binding_registered`, `di.instance_requested`,
/// `di.instance_created`, `di.cache_hit`, `di.cache_miss`,
/// `di.diagnostic`. Fields are `scope`, `modules`, `type`, `name`, `chain`,
/// `message`, and for an error `error` (its type) and `stack_trace`.
///
/// **An instance is never logged** — only the name and type it is bound
/// under. A container holds the app's configuration, clients and token
/// stores, and an object printed is whatever it holds printed. For the same
/// reason an error is logged by its type, not its text, and the `details`
/// of a warning or diagnostic are left out.
///
/// It implements the interface rather than extending
/// `SilentCherryPickObserver`: the container skips calling an observer that
/// is one, which would silence this too.
class StructuredLogCherryPickObserver implements CherryPickObserver {
  final BoundLogger? _logger;

  /// The name passed to `getLogger` when no logger was given; it lands in
  /// the `logger` field of every entry.
  final String loggerName;

  /// Bound under `category` on every entry; `null` binds nothing, leaving
  /// whatever category the logger already carries.
  final String? category;

  /// The level of each hook; see [DiLogLevels].
  final DiLogLevels levels;

  /// Creates the observer.
  ///
  /// Without a [logger] it calls `getLogger(loggerName)` on every entry
  /// rather than once, so a later `StructlogConfiguration.configure` reaches
  /// an observer installed before it.
  StructuredLogCherryPickObserver({
    BoundLogger? logger,
    this.loggerName = 'di',
    this.category = 'di',
    this.levels = const DiLogLevels(),
  }) : _logger = logger;

  @override
  void onScopeOpened(String name) =>
      _log(levels.scopeOpened, 'di.scope_opened', () => {'scope': name});

  @override
  void onScopeClosed(String name) =>
      _log(levels.scopeClosed, 'di.scope_closed', () => {'scope': name});

  @override
  void onModulesInstalled(List<String> moduleNames, {String? scopeName}) =>
      _log(levels.modulesInstalled, 'di.modules_installed', () {
        return {'modules': List.of(moduleNames), ..._scope(scopeName)};
      });

  @override
  void onModulesRemoved(List<String> moduleNames, {String? scopeName}) =>
      _log(levels.modulesRemoved, 'di.modules_removed', () {
        return {'modules': List.of(moduleNames), ..._scope(scopeName)};
      });

  @override
  void onBindingRegistered(String name, Type type, {String? scopeName}) =>
      _log(levels.bindingRegistered, 'di.binding_registered', () {
        return _binding(name, type, scopeName);
      });

  @override
  void onInstanceRequested(String name, Type type, {String? scopeName}) =>
      _log(levels.instanceRequested, 'di.instance_requested', () {
        return _binding(name, type, scopeName);
      });

  @override
  void onInstanceCreated(
    String name,
    Type type,
    Object instance, {
    String? scopeName,
  }) =>
      _log(levels.instanceCreated, 'di.instance_created', () {
        return _binding(name, type, scopeName);
      });

  @override
  void onInstanceDisposed(
    String name,
    Type type,
    Object instance, {
    String? scopeName,
  }) =>
      _log(levels.instanceDisposed, 'di.instance_disposed', () {
        return _binding(name, type, scopeName);
      });

  @override
  void onCacheHit(String name, Type type, {String? scopeName}) =>
      _log(levels.cacheHit, 'di.cache_hit', () {
        return _binding(name, type, scopeName);
      });

  @override
  void onCacheMiss(String name, Type type, {String? scopeName}) =>
      _log(levels.cacheMiss, 'di.cache_miss', () {
        return _binding(name, type, scopeName);
      });

  @override
  void onCycleDetected(List<String> chain, {String? scopeName}) =>
      _log(levels.cycleDetected, 'di.cycle_detected', () {
        return {'chain': List.of(chain), ..._scope(scopeName)};
      });

  @override
  void onDiagnostic(String message, {Object? details}) =>
      _log(levels.diagnostic, 'di.diagnostic', () => {'message': message});

  @override
  void onWarning(String message, {Object? details}) =>
      _log(levels.warning, 'di.warning', () => {'message': message});

  @override
  void onError(String message, Object? error, StackTrace? stackTrace) =>
      _log(levels.error, 'di.error', () {
        return {
          'message': message,
          if (error != null) 'error': error.runtimeType.toString(),
          if (stackTrace != null && stackTrace != StackTrace.empty)
            'stack_trace': stackTrace.toString(),
        };
      });

  Map<String, dynamic> _binding(String name, Type type, String? scopeName) =>
      {'type': type.toString(), 'name': name, ..._scope(scopeName)};

  Map<String, dynamic> _scope(String? scopeName) =>
      scopeName == null ? const {} : {'scope': scopeName};

  /// The observer is called from inside the container, mid-resolve, so
  /// nothing it does may change what the container does: a logger that
  /// throws costs the entry, never the resolve.
  void _log(
    LogLevel? level,
    String event,
    Map<String, dynamic> Function() fields,
  ) {
    if (level == null) return;
    try {
      (_logger ?? getLogger(loggerName)).tryLog(
        level,
        event,
        context: {
          if (category != null) 'category': category,
          ...fields(),
        },
      );
    } catch (_) {
      // Deliberately dropped: there is nowhere safe to report it from here.
    }
  }
}
