/// Logs what a `shelf` server receives and answers through `structured_log`.
///
/// See [structuredLogRequests] — a `Middleware` to put first in a
/// `Pipeline` — and [StructuredLogRequest], which gives a handler the logger
/// bound to its request.
library;

export 'src/shelf_middleware.dart'
    show
        ShelfLogLevels,
        StructuredLogRequest,
        defaultRedactedHeaders,
        defaultRedactedQueryParameters,
        defaultRequestIdHeader,
        redactedValue,
        structuredLogRequests;
