/// Logs what an `auto_route` router does — pushes, pops, removals, tab
/// changes — through `structured_log`.
///
/// See [StructuredLogAutoRouteObserver].
library;

export 'src/auto_route_observer.dart'
    show
        RouteLogLevels,
        StructuredLogAutoRouteObserver,
        defaultRedactedParameters,
        redactedValue;
