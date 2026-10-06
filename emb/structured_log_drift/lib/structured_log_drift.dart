/// Logs drift queries through `structured_log`.
///
/// See [StructuredLogDriftInterceptor] — pass it to `interceptWith`, and
/// every query, batch, failure and transaction end reaches the sinks, the
/// in-app viewer and the server that `structured_log` is configured with.
library;

export 'src/drift_interceptor.dart'
    show
        DriftLogLevels,
        StructuredLogDriftInterceptor,
        defaultArgumentMaxLength,
        defaultStatementMaxLength;
