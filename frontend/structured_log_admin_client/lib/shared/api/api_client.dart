import 'package:dio/dio.dart';

import '../auth/token_pair.dart';
import '../auth/token_storage.dart';
import '../config/app_config.dart';
import 'auth_api.dart';
import 'auth_interceptor.dart';
import 'logs_api.dart';
import 'resources_api.dart';

/// Everything this client uses to talk to `structured_log_server`, built once
/// and handed out by the DI root.
///
/// Holds three `Dio` instances rather than one, which is the part worth
/// understanding:
///
/// - [dio] — what every repository calls through. It carries the auth
///   interceptor, so requests get a token and a 401 gets one renewal.
/// - the refresh client — has no interceptor at all. A refresh that answered
///   401 on the main instance would re-enter the interceptor that issued it.
/// - the retry client — also uninterceptored, used to replay the original
///   request once the new token is in hand.
///
/// [dio] is also what section 22's hand-written `GET /v1/logs/stream` will
/// use: the stream needs the same base URL and the same Authorization header,
/// and only its timeouts differ (decision 37).
class ApiClient {
  final Dio dio;

  final AuthApi auth;
  final GroupsApi groups;
  final ProjectsApi projects;
  final SecretKeysApi secretKeys;
  final LogsApi logs;

  ApiClient._({
    required this.dio,
    required this.auth,
    required this.groups,
    required this.projects,
    required this.secretKeys,
    required this.logs,
  });

  factory ApiClient({
    required AppConfig config,
    required TokenStorage storage,
    void Function()? onSessionExpired,

    /// Swapped in tests for an adapter that answers without a socket.
    HttpClientAdapter? adapter,
  }) {
    BaseOptions optionsFor(Duration timeout) => BaseOptions(
      baseUrl: config.baseUrl,
      connectTimeout: timeout,
      receiveTimeout: timeout,
      sendTimeout: timeout,
      // The client decides what a status means; dio raising for it would
      // turn every 403 into an exception before the mapper sees the body.
      validateStatus: (status) => status != null && status < 400,
    );

    final dio = Dio(optionsFor(config.requestTimeout));
    final refreshClient = Dio(optionsFor(config.requestTimeout));
    final retryClient = Dio(optionsFor(config.requestTimeout));

    if (adapter != null) {
      dio.httpClientAdapter = adapter;
      refreshClient.httpClientAdapter = adapter;
      retryClient.httpClientAdapter = adapter;
    }

    final refreshApi = AuthApi(refreshClient);

    dio.interceptors.add(
      AuthInterceptor(
        storage: storage,
        retryClient: retryClient,
        onSessionExpired: onSessionExpired,
        refresh: (refreshToken) async {
          try {
            final response = await refreshApi.refresh(
              AuthApi.refreshGrant,
              refreshToken,
            );
            return TokenPair(
              accessToken: response.accessToken,
              refreshToken: response.refreshToken,
            );
          } on DioException {
            // Any failure here — refused, offline, timed out — ends the
            // session. Distinguishing them would only offer the user a retry
            // of something they cannot influence.
            return null;
          }
        },
      ),
    );

    return ApiClient._(
      dio: dio,
      auth: AuthApi(dio),
      groups: GroupsApi(dio),
      projects: ProjectsApi(dio),
      secretKeys: SecretKeysApi(dio),
      logs: LogsApi(dio),
    );
  }
}
