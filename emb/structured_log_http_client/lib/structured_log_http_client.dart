/// Logs what a `package:http` client sends and receives through
/// `structured_log`.
///
/// See [StructuredLogHttpClient] — an `http.Client` that wraps another and
/// logs every call it passes through.
library;

export 'src/http_client.dart'
    show
        HttpBodyDescriber,
        HttpLogLevels,
        StructuredLogHttpClient,
        defaultHttpBodyMaxLength,
        defaultRedactedBodyFields,
        defaultRedactedHeaders,
        defaultRedactedQueryParameters,
        describeHttpBody,
        redactedValue;
