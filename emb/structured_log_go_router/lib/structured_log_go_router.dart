/// Logs what a `GoRouter` does — navigations, redirects, routing errors —
/// through `structured_log`.
///
/// See [StructuredLogGoRouter].
library;

export 'src/go_router_logging.dart'
    show
        RouteLogLevels,
        StructuredLogGoRouter,
        defaultRedactedQueryParameters,
        redactedValue;
