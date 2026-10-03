/// Logs what a `Dio` client sends and receives through `structured_log`.
///
/// See [StructuredLogDioInterceptor] — an `Interceptor` to add to
/// `dio.interceptors`.
library;

export 'src/dio_interceptor.dart'
    show
        HttpBodyDescriber,
        HttpLogLevels,
        StructuredLogDioInterceptor,
        defaultHttpBodyMaxLength,
        defaultRedactedBodyFields,
        defaultRedactedHeaders,
        defaultRedactedQueryParameters,
        describeHttpBody,
        redactedValue;
