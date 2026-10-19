import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart' show Route;
import 'package:structured_log/structured_log.dart';

/// What a redacted parameter value is replaced with.
///
/// Plain letters rather than something like `<redacted>`: a query value is
/// percent-encoded when the location is rebuilt, and `%3Credacted%3E` reads
/// worse in a log than the word itself.
const String redactedValue = 'REDACTED';

/// Parameter names whose values never reach the log, compared
/// case-insensitively — path parameters, query parameters, and a fragment
/// written as a query, the way an OAuth implicit-flow callback carries
/// `#access_token=...`.
const Set<String> defaultRedactedParameters = {
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
  /// A screen was opened.
  final LogLevel? pushed;

  /// A screen was closed.
  final LogLevel? popped;

  /// A screen left the stack without a pop — what a `replace` does to the
  /// screen it replaces.
  final LogLevel? removed;

  /// The navigator reported a replacement itself. `auto_route` does not
  /// today: its stack is page-based, so a replacement arrives as a push and
  /// a removal.
  final LogLevel? replaced;

  /// A tab of a `TabsRouter` was activated or switched to.
  final LogLevel? tabChanged;

  const RouteLogLevels({
    this.pushed = LogLevel.info,
    this.popped = LogLevel.info,
    this.removed = LogLevel.info,
    this.replaced = LogLevel.info,
    this.tabChanged = LogLevel.info,
  });
}

/// Writes what an `auto_route` router does to `structured_log`.
///
/// ```dart
/// MaterialApp.router(
///   routerConfig: appRouter.config(
///     navigatorObservers: () => [StructuredLogAutoRouteObserver()],
///   ),
/// );
/// ```
///
/// Every entry carries `category` (`navigation` by default) and describes
/// the screen it is about:
///
/// - `route` — the route's name, such as `UserRoute`;
/// - `route_path` — its path pattern, such as `/user/:id`;
/// - `location` — where it actually is, such as `/user/7?tab=1`, with the
///   values of [redactedParameters] replaced by [redactedValue].
///
/// The events:
///
/// - `route_pushed` — a screen was opened; `previous_route`/
///   `previous_location` name the one below it.
/// - `route_popped` — a screen was closed; the previous fields name the one
///   that shows again.
/// - `route_removed` — a screen left the stack without a pop. A `replace`
///   arrives as `route_pushed` for the new screen and `route_removed` for
///   the old one.
/// - `route_tab_changed` — a tab was activated (`tab_event: init`) or
///   switched to (`tab_event: change`), with `tab_index` and, when known,
///   `previous_route`.
///
/// What it cannot see: a route that is updated in place (`navigatePath` to
/// the open route with other parameters) never reaches a `NavigatorObserver`,
/// nor does a path no route matches, nor what a guard decides. A screen
/// opened outside the router (a dialog, a bottom sheet) is logged by its
/// settings name or type and has no `location`.
class StructuredLogAutoRouteObserver extends AutoRouterObserver {
  final BoundLogger? _logger;

  /// The name passed to `getLogger` when no logger was given; it lands in
  /// the `logger` field of every entry.
  final String loggerName;

  /// Bound under `category` on every entry; `null` binds nothing, leaving
  /// whatever category the logger already carries.
  final String? category;

  /// The level of each kind of entry; see [RouteLogLevels].
  final RouteLogLevels levels;

  /// Parameter names, lower case, whose values are replaced with
  /// [redactedValue].
  final Set<String> redactedParameters;

  /// When given, only routes for which it returns `true` are logged. An
  /// entry about a route it rejects is left out; an entry whose
  /// neighbour (`previous_route`) it rejects is written without the
  /// neighbour. A filter that throws rejects. A screen with no route
  /// match (a dialog) is not filtered.
  final bool Function(RouteMatch route)? filter;

  /// Creates the observer.
  ///
  /// Without a [logger] it calls `getLogger(loggerName)` on every entry
  /// rather than once, so a later `StructlogConfiguration.configure`
  /// reaches a router set up before it.
  StructuredLogAutoRouteObserver({
    BoundLogger? logger,
    this.loggerName = 'router',
    this.category = 'navigation',
    this.levels = const RouteLogLevels(),
    this.redactedParameters = defaultRedactedParameters,
    this.filter,
  }) : _logger = logger;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _logRoute(levels.pushed, 'route_pushed', route, previousRoute);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _logRoute(levels.popped, 'route_popped', route, previousRoute);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _logRoute(levels.removed, 'route_removed', route, previousRoute);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute == null) return;
    _logRoute(levels.replaced, 'route_replaced', newRoute, oldRoute);
  }

  @override
  void didInitTabRoute(TabPageRoute route, TabPageRoute? previousRoute) =>
      _logTab('init', route, previousRoute);

  @override
  void didChangeTabRoute(TabPageRoute route, TabPageRoute previousRoute) =>
      _logTab('change', route, previousRoute);

  void _logRoute(
    LogLevel? level,
    String event,
    Route<dynamic> route,
    Route<dynamic>? previous,
  ) {
    _emit(
      level,
      event,
      () => _routeFields(route),
      () => previous == null ? null : _routeFields(previous, neighbour: true),
    );
  }

  void _logTab(String tabEvent, TabPageRoute route, TabPageRoute? previous) {
    _emit(
      levels.tabChanged,
      'route_tab_changed',
      () => _matchFields(route.routeInfo, const []),
      () =>
          previous == null ? null : _matchFields(previous.routeInfo, const []),
      extra: {'tab_event': tabEvent, 'tab_index': route.index},
    );
  }

  /// Builds the entry only once it is known to be wanted, and never lets
  /// anything it does reach the navigator: the hooks run inside
  /// `Navigator`, so an exception here would be a navigation failure.
  ///
  /// [subject] is `null` for an entry [filter] rejects, and the entry is
  /// then not written at all; the same for [neighbour] only drops the
  /// `previous_*` fields.
  void _emit(
    LogLevel? level,
    String event,
    Map<String, dynamic>? Function() subject,
    Map<String, dynamic>? Function() neighbour, {
    Map<String, dynamic> extra = const {},
  }) {
    if (level == null) return;
    try {
      final logger = _logger ?? getLogger(loggerName);
      if (!logger.isEnabled(level)) return;
      final fields = subject();
      if (fields == null) return;
      final previous = neighbour();
      logger.tryLog(
        level,
        event,
        context: {
          if (category != null) 'category': category,
          ...fields,
          ...extra,
          if (previous != null) ...{
            'previous_route': previous['route'],
            if (previous['location'] != null)
              'previous_location': previous['location'],
          },
        },
      );
    } catch (_) {
      // Deliberately dropped: there is nowhere safe to report it from here.
    }
  }

  /// The fields describing [route], or `null` when [filter] rejects it.
  ///
  /// A [neighbour] is described by its path alone: `auto_route` keeps the
  /// query of the navigation in progress on the router, not on each route,
  /// so a neighbour's own query cannot be told from the one that is moving.
  Map<String, dynamic>? _routeFields(
    Route<dynamic> route, {
    bool neighbour = false,
  }) {
    final data = route.data;
    if (data == null) {
      return {'route': route.settings.name ?? route.runtimeType.toString()};
    }
    final ancestors = <RouteMatch>[];
    for (var parent = data.parent; parent != null; parent = parent.parent) {
      ancestors.insert(0, parent.route);
    }
    return _matchFields(data.route, ancestors, neighbour: neighbour);
  }

  /// The fields describing [match] below [ancestors] (outermost first), or
  /// `null` when [filter] rejects it.
  Map<String, dynamic>? _matchFields(
    RouteMatch match,
    List<RouteMatch> ancestors, {
    bool neighbour = false,
  }) {
    if (!_passes(match)) return null;
    try {
      final chain = [...ancestors, match];
      return {
        'route': match.name,
        'route_path': _join([for (final each in chain) each.path]),
        'location': _location(chain, withQuery: !neighbour),
      };
    } catch (error) {
      return {
        'route': match.name,
        'route_failed': error.runtimeType.toString(),
      };
    }
  }

  /// Whether [filter] lets [route] be logged; a filter that throws does not.
  bool _passes(RouteMatch route) {
    try {
      return filter?.call(route) ?? true;
    } catch (_) {
      return false;
    }
  }

  String _location(List<RouteMatch> chain, {required bool withQuery}) {
    final sensitive = <String>{};
    for (final each in chain) {
      for (final MapEntry(:key, :value) in each.params.rawMap.entries) {
        if (redactedParameters.contains(key.toLowerCase()) && value != null) {
          sensitive.add(value.toString());
        }
      }
    }
    final path = _join([
      for (final each in chain)
        each.stringMatch
            .split('/')
            .map(
              (segment) =>
                  sensitive.contains(segment) ||
                      sensitive.contains(_decoded(segment))
                  ? redactedValue
                  : segment,
            )
            .join('/'),
    ]);

    if (!withQuery) return path;
    final leaf = chain.last;
    final query = {
      for (final MapEntry(:key, :value) in leaf.queryParams.rawMap.entries)
        key: redactedParameters.contains(key.toLowerCase())
            ? redactedValue
            : '$value',
    };
    final fragment = _redactFragment(leaf.fragment);
    return '$path'
        '${query.isEmpty ? '' : '?${Uri(queryParameters: query).query}'}'
        '${fragment.isEmpty ? '' : '#$fragment'}';
  }

  String _redactFragment(String fragment) {
    if (!fragment.contains('=')) return fragment;
    final parts = Uri.splitQueryString(fragment);
    if (!parts.keys.any(
      (name) => redactedParameters.contains(name.toLowerCase()),
    )) {
      return fragment;
    }
    return Uri(
      queryParameters: {
        for (final MapEntry(:key, :value) in parts.entries)
          key: redactedParameters.contains(key.toLowerCase())
              ? redactedValue
              : value,
      },
    ).query;
  }

  static String _decoded(String segment) {
    try {
      return Uri.decodeComponent(segment);
    } catch (_) {
      return segment;
    }
  }

  /// [parts] joined into one absolute path, the way nested routes compose.
  static String _join(List<String> parts) {
    final segments = [
      for (final part in parts)
        for (final segment in part.split('/'))
          if (segment.isNotEmpty) segment,
    ];
    return '/${segments.join('/')}';
  }
}
