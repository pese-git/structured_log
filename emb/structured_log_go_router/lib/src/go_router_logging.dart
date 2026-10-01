import 'package:go_router/go_router.dart';
import 'package:structured_log/structured_log.dart';

/// What a redacted query parameter value is replaced with.
///
/// Plain letters rather than something like `<redacted>`: a query value is
/// percent-encoded when the location is rebuilt, and `%3Credacted%3E` reads
/// worse in a log than the word itself.
const String redactedValue = 'REDACTED';

/// Query parameters whose values never reach the log, compared
/// case-insensitively — in the query and in a fragment written as one, the
/// way an OAuth implicit-flow callback carries `#access_token=...`.
const Set<String> defaultRedactedQueryParameters = {
  'access_token',
  'refresh_token',
  'id_token',
  'token',
  'api_key',
  'apikey',
  'password',
  'client_secret',
  'code',
};

/// The level each kind of entry is logged at; `null` turns it off.
class RouteLogLevels {
  /// The router settled on a new location.
  final LogLevel? navigation;

  /// A redirect sent a navigation somewhere else.
  final LogLevel? redirect;

  /// A location matched no route, or routing failed in some other way.
  final LogLevel? error;

  const RouteLogLevels({
    this.navigation = LogLevel.info,
    this.redirect = LogLevel.debug,
    this.error = LogLevel.warning,
  });
}

/// Writes what a [GoRouter] does to `structured_log`.
///
/// ```dart
/// final routeLog = StructuredLogGoRouter();
/// final router = GoRouter(
///   routes: [...],
///   redirect: routeLog.redirect(authRedirect), // optional
/// );
/// routeLog.attach(router);
/// ```
///
/// Three entries, all carrying `category` (`navigation` by default):
///
/// - `route_changed` — the router settled on a new location: `location`,
///   `route` (the matched pattern, such as `/users/:id`), `route_name` when
///   the route has one, and `previous_location`/`previous_route`. Logged by
///   [attach], which listens to the router; pushes and pops count.
/// - `route_redirected` — a redirect wrapped with [redirect] sent the
///   navigation elsewhere: `from`, `to`.
/// - `route_error` — no route matched, or routing failed: `location`,
///   `error`. Logged by [attach] when the router shows its error page, or
///   by [onException] when the app handles the error itself.
///
/// Locations are logged as they are, path parameters included, except that
/// the values of [redactedQueryParameters] — in the query, and in a
/// fragment shaped like one — are replaced with [redactedValue]. Neither
/// `extra` nor route state objects are logged.
///
/// Only the router's own pages are seen: a dialog or bottom sheet pushed
/// through `Navigator` directly is not a location and does not appear.
class StructuredLogGoRouter {
  final BoundLogger? _logger;

  /// The name passed to `getLogger` when no logger was given; it lands in
  /// the `logger` field of every entry.
  final String loggerName;

  /// Bound under `category` on every entry; `null` binds nothing, leaving
  /// whatever category the logger already carries.
  final String? category;

  /// The level of each kind of entry; see [RouteLogLevels].
  final RouteLogLevels levels;

  /// Query parameter names, lower case, whose values are replaced with
  /// [redactedValue].
  final Set<String> redactedQueryParameters;

  /// When given, only navigations to a state for which it returns `true`
  /// produce a `route_changed` entry. Redirects and errors are not
  /// filtered.
  final bool Function(GoRouterState state)? filter;

  GoRouter? _router;
  Object? _lastConfiguration;
  String? _lastLocation;
  String? _lastRoute;

  /// Creates the logger; nothing is logged until [attach] — or a wrapped
  /// [redirect]/[onException] runs.
  ///
  /// Without a [logger] it calls `getLogger(loggerName)` on every entry
  /// rather than once, so a later `StructlogConfiguration.configure`
  /// reaches a router set up before it.
  StructuredLogGoRouter({
    BoundLogger? logger,
    this.loggerName = 'router',
    this.category = 'navigation',
    this.levels = const RouteLogLevels(),
    this.redactedQueryParameters = defaultRedactedQueryParameters,
    this.filter,
  }) : _logger = logger;

  /// Starts logging [router]'s navigations — including the location it is
  /// already on, if it has settled on one.
  ///
  /// Attaching again moves the listener to the new router; [detach] stops
  /// it. The router does not have to outlive this object or the other way
  /// round, but a router that is disposed while attached must be detached
  /// first, the way any listener is removed before its notifier goes.
  void attach(GoRouter router) {
    detach();
    _router = router;
    router.routerDelegate.addListener(_onRouteChanged);
    _onRouteChanged();
  }

  /// Stops logging the attached router's navigations; does nothing if
  /// none is attached.
  void detach() {
    _router?.routerDelegate.removeListener(_onRouteChanged);
    _router = null;
    _lastConfiguration = null;
    _lastLocation = null;
    _lastRoute = null;
  }

  /// Wraps a top-level or route-level redirect so that every redirect it
  /// makes is logged as `route_redirected`.
  ///
  /// The wrapped function's answer — and its exceptions — reach the router
  /// unchanged, and a synchronous redirect stays synchronous.
  GoRouterRedirect redirect(GoRouterRedirect inner) {
    return (context, state) {
      final result = inner(context, state);
      if (result is Future<String?>) {
        return result.then((to) {
          _guard(() => _logRedirect(state, to));
          return to;
        });
      }
      _guard(() => _logRedirect(state, result));
      return result;
    };
  }

  /// Wraps a `GoRouter.onException` handler so that every routing error it
  /// is handed is logged as `route_error` first.
  ///
  /// With `onException` set, the router does not show its error page, so
  /// [attach] never sees these errors; this is how they reach the log.
  GoExceptionHandler onException(GoExceptionHandler inner) {
    return (context, state, router) {
      _guard(() => _logError(state.uri, state.error));
      inner(context, state, router);
    };
  }

  void _onRouteChanged() {
    _guard(() {
      final delegate = _router?.routerDelegate;
      if (delegate == null) return;
      final configuration = delegate.currentConfiguration;
      // The delegate notifies for more than navigation; only a new match
      // list is a new location.
      if (configuration == _lastConfiguration) return;
      // An error has no matches at all, so it is told apart before the
      // empty list a router has until it settles.
      if (configuration.isError) {
        _lastConfiguration = configuration;
        _logError(configuration.uri, configuration.error);
        return;
      }
      if (configuration.isEmpty) return;
      _lastConfiguration = configuration;

      final state = delegate.state;
      final location = _redact(state.uri);
      final route = state.fullPath;
      final previousLocation = _lastLocation;
      final previousRoute = _lastRoute;
      _lastLocation = location;
      _lastRoute = route;
      if (filter != null && !filter!(state)) return;

      _log(levels.navigation, 'route_changed', {
        'location': location,
        if (route != null && route.isNotEmpty) 'route': route,
        if (state.name != null) 'route_name': state.name,
        if (previousLocation != null) 'previous_location': previousLocation,
        if (previousRoute != null && previousRoute.isNotEmpty)
          'previous_route': previousRoute,
      });
    });
  }

  void _logRedirect(GoRouterState state, String? to) {
    if (to == null) return;
    final from = _redact(state.uri);
    final target = _redact(Uri.parse(to));
    if (from == target) return;
    _log(levels.redirect, 'route_redirected', {'from': from, 'to': target});
  }

  void _logError(Uri location, GoException? error) {
    _log(levels.error, 'route_error', {
      'location': _redact(location),
      if (error != null) 'error': error.message,
    });
  }

  /// Logging runs inside the router's own notification and redirect
  /// calls, so nothing it does may change how navigation goes.
  void _guard(void Function() body) {
    try {
      body();
    } catch (_) {
      // Deliberately dropped: there is nowhere safe to report it from here.
    }
  }

  void _log(LogLevel? level, String event, Map<String, dynamic> fields) {
    if (level == null) return;
    (_logger ?? getLogger(loggerName)).tryLog(
      level,
      event,
      context: {if (category != null) 'category': category, ...fields},
    );
  }

  String _redact(Uri uri) {
    var redacted = uri;
    if (_hasRedactedName(uri.queryParametersAll.keys)) {
      redacted = redacted.replace(
        queryParameters: _redactParameters(uri.queryParametersAll),
      );
    }
    if (uri.fragment.contains('=')) {
      final fragment = Uri.splitQueryString(uri.fragment);
      if (_hasRedactedName(fragment.keys)) {
        redacted = redacted.replace(
          fragment: Uri(
            queryParameters: _redactParameters({
              for (final MapEntry(:key, :value) in fragment.entries)
                key: [value],
            }),
          ).query,
        );
      }
    }
    return redacted.toString();
  }

  bool _hasRedactedName(Iterable<String> names) =>
      names.any((name) => redactedQueryParameters.contains(name.toLowerCase()));

  Map<String, List<String>> _redactParameters(
    Map<String, List<String>> parameters,
  ) => {
    for (final MapEntry(:key, :value) in parameters.entries)
      key: redactedQueryParameters.contains(key.toLowerCase())
          ? [for (final _ in value) redactedValue]
          : value,
  };
}
