import 'package:cherrypick/cherrypick.dart';
import 'package:dio/dio.dart';

import '../auth/token_pair.dart';
import '../auth/token_storage.dart';
import '../config/app_config.dart';
import 'audit_api.dart';
import 'auth_api.dart';
import 'auth_interceptor.dart';
import 'logs_api.dart';
import 'resources_api.dart';
import 'streaming/streaming_adapter.dart';
import 'users_api.dart';

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
/// [streamDio] is the fourth, and it exists only because of the web. The
/// live log subscription needs the same base URL, the same Authorization
/// header and the same refresh as everything else — so it shares the very
/// interceptor *instance*, which is what keeps "one refresh in flight" true
/// across both — but it also needs a response delivered as it arrives, and
/// dio's browser adapter cannot do that (see `streaming_adapter_web.dart`).
/// Off the web it is an ordinary `Dio` with no adapter of its own.
class ApiClient implements Disposable {
  final Dio dio;

  /// What `GET /v1/logs/stream` runs on (decision 37).
  final Dio streamDio;

  final AuthApi auth;
  final AuditApi audit;
  final GroupsApi groups;
  final TeamsApi teams;
  final ProjectsApi projects;
  final SecretKeysApi secretKeys;
  final LogsApi logs;
  final UsersApi users;
  final RoleAssignmentsApi roleAssignments;

  /// Every `Dio` this client created, [dio] and [streamDio] included — the
  /// two uninterceptored ones live only inside the interceptor.
  final List<Dio> _owned;

  ApiClient._({
    required this.dio,
    required this.streamDio,
    required this.auth,
    required this.audit,
    required this.groups,
    required this.teams,
    required this.projects,
    required this.secretKeys,
    required this.logs,
    required this.users,
    required this.roleAssignments,
    required List<Dio> owned,
  }) : _owned = owned;

  factory ApiClient({
    required AppConfig config,
    required TokenStorage storage,
    void Function()? onSessionExpired,
    void Function()? onPasswordChangeRequired,

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
    // No send/receive deadline: a live subscription is a body that stays open
    // on purpose, and `LogStreamClient` applies its own idle timeout per
    // request. Connecting still has one.
    final streamDio = Dio(
      optionsFor(config.requestTimeout)
        ..receiveTimeout = null
        ..sendTimeout = null,
    );

    final streamingAdapter = createStreamingAdapter();
    if (streamingAdapter != null) {
      streamDio.httpClientAdapter = streamingAdapter;
    }

    if (adapter != null) {
      dio.httpClientAdapter = adapter;
      refreshClient.httpClientAdapter = adapter;
      retryClient.httpClientAdapter = adapter;
      // A test that answers without a socket answers for the stream too, and
      // its adapter outranks the platform one.
      streamDio.httpClientAdapter = adapter;
    }

    final refreshApi = AuthApi(refreshClient);

    final authInterceptor = AuthInterceptor(
      storage: storage,
      retryClient: retryClient,
      onSessionExpired: onSessionExpired,
      onPasswordChangeRequired: onPasswordChangeRequired,
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
    );

    // The same object in both, not two of them: the guard that collapses
    // parallel 401s into one refresh lives in the instance.
    dio.interceptors.add(authInterceptor);
    streamDio.interceptors.add(authInterceptor);

    return ApiClient._(
      dio: dio,
      streamDio: streamDio,
      auth: AuthApi(dio),
      audit: AuditApi(dio),
      groups: GroupsApi(dio),
      teams: TeamsApi(dio),
      projects: ProjectsApi(dio),
      secretKeys: SecretKeysApi(dio),
      logs: LogsApi(dio),
      users: UsersApi(dio),
      roleAssignments: RoleAssignmentsApi(dio),
      owned: [dio, streamDio, refreshClient, retryClient],
    );
  }

  /// Called by the scope that created this client when it is disposed: closes
  /// the connections it holds. `force`, because a scope going away is not a
  /// request to wait for whatever is still in flight — including a live
  /// subscription that would otherwise never end.
  @override
  Future<void> dispose() async {
    for (final client in _owned) {
      client.close(force: true);
    }
  }
}
