/// Where this client points and how it behaves at runtime.
///
/// Passed in at composition time rather than read from a global: the gallery,
/// the tests and a real deployment all supply their own, and nothing below the
/// DI root reaches for it.
class AppConfig {
  /// Origin of the `structured_log_server` instance, without a trailing
  /// slash — e.g. `https://logs.example.com`.
  final String baseUrl;

  /// How long a single request may take before it is treated as a network
  /// failure. The live log stream is exempt: it is a long-lived body by
  /// design and sets its own timeouts (decision 37, section 22).
  final Duration requestTimeout;

  const AppConfig({
    required this.baseUrl,
    this.requestTimeout = const Duration(seconds: 30),
  });
}
