import '../auth/hashing.dart' show passwordPolicyMessage;
import '../auth/token_settings.dart'
    show jwtSecretPolicyMessage, minJwtSecretBytes;
import 'config_resolver.dart';
import 'param_spec.dart';

/// Subcommand names `bin/server.dart` accepts — used only to decide which
/// [ParamSpec.requiredForCommands] apply (`log-server-config`: required
/// params depend on the command being run).
const commandServe = 'serve';
const commandCreateAdmin = 'create-admin';

/// `db-backend`'s default ('sqlite') applies the same whether the value is
/// literally absent or literally `'sqlite'` — both `requiredWhen` predicates
/// below treat the two identically, matching how every other parameter's own
/// resolution already treats "not set" as "the default value".
bool _sqliteBackend(Map<String, Object?> values) =>
    (values['db-backend'] as String? ?? 'sqlite') == 'sqlite';
bool _postgresBackend(Map<String, Object?> values) =>
    values['db-backend'] == 'postgres';

/// Every configuration parameter the implemented capabilities need, declared
/// once — the single source [ConfigResolver] builds the CLI parser, env var
/// names, and `--help`/`--print-config` output from. Fields for capabilities
/// not yet built (`registrationEnabled`, password-reset/email-verification
/// base URLs, SMTP — `design.md` "Delivery Phases") are added here alongside
/// those capabilities, not before.
const serverConfigParams = <ParamSpec>[
  // Declared before `db-path`/`db-postgres-*`: their `requiredWhen` reads
  // this value, and `ConfigResolver` resolves specs in list order
  // (`add-postgres-backend` design.md, decision 1a).
  ParamSpec(
    name: 'db-backend',
    type: ParamType.string,
    description:
        'Storage backend: "sqlite" (default, a local file) or '
        '"postgres" (an operator-managed PostgreSQL server).',
    defaultValue: 'sqlite',
    allowedValues: {'sqlite', 'postgres'},
  ),
  ParamSpec(
    name: 'db-path',
    type: ParamType.string,
    description:
        'Path to the SQLite database file. Only used, and only '
        'required, when db-backend=sqlite (the default).',
    requiredForCommands: {commandServe, commandCreateAdmin},
    requiredWhen: _sqliteBackend,
  ),
  ParamSpec(
    name: 'db-postgres-host',
    type: ParamType.string,
    description: 'PostgreSQL host. Required when db-backend=postgres.',
    requiredForCommands: {commandServe, commandCreateAdmin},
    requiredWhen: _postgresBackend,
  ),
  ParamSpec(
    name: 'db-postgres-port',
    type: ParamType.int,
    description: 'PostgreSQL port.',
    defaultValue: 5432,
  ),
  ParamSpec(
    name: 'db-postgres-database',
    type: ParamType.string,
    description:
        'PostgreSQL database name. Required when '
        'db-backend=postgres.',
    requiredForCommands: {commandServe, commandCreateAdmin},
    requiredWhen: _postgresBackend,
  ),
  ParamSpec(
    name: 'db-postgres-username',
    type: ParamType.string,
    description: 'PostgreSQL username. Required when db-backend=postgres.',
    requiredForCommands: {commandServe, commandCreateAdmin},
    requiredWhen: _postgresBackend,
  ),
  ParamSpec(
    name: 'db-postgres-password',
    type: ParamType.string,
    description:
        'PostgreSQL password. Required when db-backend=postgres — '
        'like every other secret, no command-line flag exists for it.',
    isSecret: true,
    requiredForCommands: {commandServe, commandCreateAdmin},
    requiredWhen: _postgresBackend,
  ),
  ParamSpec(
    name: 'db-postgres-pool-size',
    type: ParamType.int,
    description:
        'PostgreSQL connection pool size — shared by reads and '
        'writes alike (unlike --db-read-pool-size, which is SQLite-only and '
        'has no effect here).',
    defaultValue: 10,
    minValue: 1,
    maxValue: 64,
  ),
  ParamSpec(
    name: 'db-postgres-ssl-mode',
    type: ParamType.string,
    description:
        'TLS mode for the PostgreSQL connection: "require" '
        '(default — encrypted, certificate errors ignored), "verify-full" '
        '(encrypted and certificate-verified), or "disable" (no TLS — for '
        'local development against a server with none configured).',
    defaultValue: 'require',
    allowedValues: {'disable', 'require', 'verify-full'},
  ),
  ParamSpec(
    name: 'http-host',
    type: ParamType.string,
    description: 'Host/address the HTTP server binds to.',
    defaultValue: '0.0.0.0',
  ),
  ParamSpec(
    name: 'http-port',
    type: ParamType.int,
    description: 'Port the HTTP server listens on.',
    defaultValue: 8080,
  ),
  ParamSpec(
    name: 'jwt-secret',
    type: ParamType.string,
    description:
        'HMAC secret access tokens are signed with; at least '
        '$minJwtSecretBytes bytes.',
    isSecret: true,
    requiredForCommands: {commandServe},
    // Refuses to start rather than warning. A secret short enough to search
    // for offline turns one captured token into an `admin` one somebody
    // signed themselves, and a warning at startup in a JSON log is a thing
    // nobody reads twice (`auth/token_settings.dart`).
    validator: jwtSecretPolicyMessage,
  ),
  ParamSpec(
    name: 'jwt-issuer',
    type: ParamType.string,
    description: 'The `iss` claim embedded in access tokens.',
    defaultValue: 'structured_log_server',
  ),
  ParamSpec(
    name: 'max-ingest-body-bytes',
    type: ParamType.int,
    description: 'Maximum accepted POST /v1/logs request body size, in bytes.',
    defaultValue: 10 * 1024 * 1024,
  ),
  ParamSpec(
    name: 'retention-purge-interval-seconds',
    type: ParamType.int,
    description: 'How often the retention purge job runs, in seconds.',
    defaultValue: 3600,
  ),
  ParamSpec(
    name: 'bootstrap-admin-enabled',
    type: ParamType.bool,
    description: 'Auto-create the first administrator on an empty database.',
    defaultValue: true,
  ),
  ParamSpec(
    name: 'bootstrap-admin-username',
    type: ParamType.string,
    description: 'Username for the auto-created first administrator.',
    defaultValue: 'admin',
  ),
  ParamSpec(
    name: 'bootstrap-admin-password',
    type: ParamType.string,
    description:
        'Password for the administrator created by auto-bootstrap or by '
        'the create-admin command. Unset means generate one randomly and '
        'require it to be changed at first login — same behavior in both '
        'cases (`log-server-config`: create-admin has no required '
        'parameter beyond db-path). When set it must be 8 characters to '
        '72 bytes, like any password set through the API.',
    isSecret: true,
    validator: passwordPolicyMessage,
  ),
  ParamSpec(
    name: 'log-level',
    type: ParamType.string,
    description: "The server's own minimum diagnostic log level.",
    defaultValue: 'info',
    allowedValues: {'trace', 'debug', 'info', 'warning', 'error', 'critical'},
  ),
  ParamSpec(
    name: 'audit-retention-days',
    type: ParamType.int,
    description:
        'Delete administrative audit records older than this many days. '
        'Unset keeps them indefinitely.',
    mustBePositive: true,
  ),
  ParamSpec(
    name: 'auth-event-retention-days',
    type: ParamType.int,
    description:
        'Delete authentication audit records (auth.*) older than this many '
        'days. Unset keeps them indefinitely.',
    mustBePositive: true,
  ),
  ParamSpec(
    name: 'audit-purge-batch-size',
    type: ParamType.int,
    description: 'How many audit records one purge chunk deletes.',
    defaultValue: 500,
    mustBePositive: true,
  ),
  ParamSpec(
    name: 'db-read-pool-size',
    type: ParamType.int,
    description:
        'Extra database connections, each on its own isolate, that '
        'serve reads beside the single writer; 0 sends every read through the '
        'writer.',
    defaultValue: 2,
    minValue: 0,
    maxValue: 16,
  ),
  ParamSpec(
    name: 'log-file',
    type: ParamType.string,
    description:
        "Path to write the server's own diagnostic log to. Unset means "
        'the console.',
  ),
  ParamSpec(
    name: 'log-format',
    type: ParamType.string,
    description: "The server's own diagnostic log output format.",
    defaultValue: 'console',
    allowedValues: {'console', 'json'},
  ),
  ParamSpec(
    name: 'log-max-file-bytes',
    type: ParamType.int,
    description: 'Rotate the log file once it exceeds this size, in bytes.',
    defaultValue: 10 * 1024 * 1024,
  ),
  ParamSpec(
    name: 'log-max-files',
    type: ParamType.int,
    description: 'How many rotated log files to keep.',
    defaultValue: 5,
  ),
  ParamSpec(
    name: 'rate-limit-enabled',
    type: ParamType.bool,
    description: 'Enable rate limiting on auth endpoints.',
    defaultValue: true,
  ),
  ParamSpec(
    name: 'rate-limit-bucket-capacity',
    type: ParamType.int,
    description: 'Token bucket capacity for both the IP and subject keys.',
    defaultValue: 10,
  ),
  ParamSpec(
    name: 'rate-limit-refill-per-minute',
    type: ParamType.int,
    description: 'Tokens restored per minute to each rate-limit bucket.',
    defaultValue: 10,
  ),
  ParamSpec(
    name: 'rate-limit-max-keys',
    type: ParamType.int,
    description:
        'Upper bound on the number of rate-limit buckets kept in memory.',
    defaultValue: 10000,
  ),
  ParamSpec(
    name: 'trusted-proxy-hops',
    type: ParamType.int,
    description:
        'Number of trusted reverse-proxy hops — controls whether '
        'X-Forwarded-For is honored for client IP resolution.',
    defaultValue: 0,
  ),
  ParamSpec(
    name: 'sse-heartbeat-interval-seconds',
    type: ParamType.int,
    description: 'Interval between GET /v1/logs/stream heartbeat pings.',
    defaultValue: 25,
  ),
  ParamSpec(
    name: 'cors-allowed-origins',
    type: ParamType.string,
    description:
        'Comma-separated list of origins allowed to make cross-origin '
        'requests. Empty (the default) means no CORS headers at all — the '
        'client is expected to be served from the same origin as the API.',
    defaultValue: '',
  ),
];

/// The fully resolved, immutable configuration Stage 1 uses. No global
/// singleton — every consumer receives it explicitly (`design.md` decision
/// 47, a deliberate contrast with `StructlogConfiguration`), so tests
/// construct one directly without touching process environment.
class ServerConfig {
  /// `sqlite` (default) or `postgres` — which of [dbPath] or the
  /// `dbPostgres*` fields below is actually populated
  /// (`add-postgres-backend` design.md, decision 1).
  final String dbBackend;

  /// Only set (and only meaningful) when [dbBackend] is `sqlite`.
  final String? dbPath;

  /// Only set (and only meaningful) when [dbBackend] is `postgres`.
  final String? dbPostgresHost;
  final int dbPostgresPort;
  final String? dbPostgresDatabase;
  final String? dbPostgresUsername;
  final String? dbPostgresPassword;
  final int dbPostgresPoolSize;

  /// `disable`/`require`/`verify-full` — kept as the raw string here (the
  /// same convention as `logLevel`/`logFormat`) rather than `package:postgres`'s
  /// `SslMode`, so this config layer stays free of a storage-layer dependency;
  /// `StructuredLogDatabase.openPostgres` maps it.
  final String dbPostgresSslMode;

  final String httpHost;
  final int httpPort;
  final String? jwtSecret;
  final String jwtIssuer;
  final int maxIngestBodyBytes;
  final int retentionPurgeIntervalSeconds;
  final bool bootstrapAdminEnabled;
  final String bootstrapAdminUsername;
  final String? bootstrapAdminPassword;
  final String logLevel;
  final String? logFile;
  final String logFormat;
  final int logMaxFileBytes;
  final int logMaxFiles;
  final bool rateLimitEnabled;
  final int rateLimitBucketCapacity;
  final int rateLimitRefillPerMinute;
  final int rateLimitMaxKeys;
  final int trustedProxyHops;
  final int sseHeartbeatIntervalSeconds;

  /// Origins allowed to receive CORS headers. Empty by default, which keeps
  /// the server's long-standing behavior: no `Access-Control-Allow-*` header
  /// on any response, for any origin (`specs/log-server-api`).
  final Set<String> corsAllowedOrigins;

  /// Both `null` by default, meaning records are kept indefinitely — which is
  /// the behaviour a server that predates this setting already had. Upgrading
  /// SHALL not delete anything on its own: an operator who deployed a year ago
  /// must not find that an upgrade quietly cleared their history
  /// (`design.md` decision 46). Turning retention on is an explicit act.
  final int? auditRetentionDays;
  final int? authEventRetentionDays;
  final int auditPurgeBatchSize;
  final int dbReadPoolSize;

  const ServerConfig({
    this.dbBackend = 'sqlite',
    this.dbPath,
    this.dbPostgresHost,
    this.dbPostgresPort = 5432,
    this.dbPostgresDatabase,
    this.dbPostgresUsername,
    this.dbPostgresPassword,
    this.dbPostgresPoolSize = 10,
    this.dbPostgresSslMode = 'require',
    required this.httpHost,
    required this.httpPort,
    required this.jwtSecret,
    required this.jwtIssuer,
    required this.maxIngestBodyBytes,
    required this.retentionPurgeIntervalSeconds,
    required this.bootstrapAdminEnabled,
    required this.bootstrapAdminUsername,
    required this.bootstrapAdminPassword,
    required this.logLevel,
    required this.logFile,
    required this.logFormat,
    required this.logMaxFileBytes,
    required this.logMaxFiles,
    required this.rateLimitEnabled,
    required this.rateLimitBucketCapacity,
    required this.rateLimitRefillPerMinute,
    required this.rateLimitMaxKeys,
    required this.trustedProxyHops,
    required this.sseHeartbeatIntervalSeconds,
    this.corsAllowedOrigins = const {},
    this.auditRetentionDays,
    this.authEventRetentionDays,
    this.auditPurgeBatchSize = 500,
    this.dbReadPoolSize = 2,
  });

  /// Builds a [ServerConfig] from [ConfigResolver.parse]'s resolved values
  /// — only valid to call on a [ConfigParseOutcome.success] or
  /// [ConfigParseOutcome.printConfig] result.
  factory ServerConfig.fromResolved(Map<String, ResolvedValue> values) {
    T get<T>(String name) => values[name]!.value as T;
    return ServerConfig(
      dbBackend: get('db-backend'),
      dbPath: get('db-path'),
      dbPostgresHost: get('db-postgres-host'),
      dbPostgresPort: get('db-postgres-port'),
      dbPostgresDatabase: get('db-postgres-database'),
      dbPostgresUsername: get('db-postgres-username'),
      dbPostgresPassword: get('db-postgres-password'),
      dbPostgresPoolSize: get('db-postgres-pool-size'),
      dbPostgresSslMode: get('db-postgres-ssl-mode'),
      httpHost: get('http-host'),
      httpPort: get('http-port'),
      jwtSecret: get('jwt-secret'),
      jwtIssuer: get('jwt-issuer'),
      maxIngestBodyBytes: get('max-ingest-body-bytes'),
      retentionPurgeIntervalSeconds: get('retention-purge-interval-seconds'),
      bootstrapAdminEnabled: get('bootstrap-admin-enabled'),
      bootstrapAdminUsername: get('bootstrap-admin-username'),
      bootstrapAdminPassword: get('bootstrap-admin-password'),
      logLevel: get('log-level'),
      logFile: get('log-file'),
      logFormat: get('log-format'),
      logMaxFileBytes: get('log-max-file-bytes'),
      logMaxFiles: get('log-max-files'),
      rateLimitEnabled: get('rate-limit-enabled'),
      rateLimitBucketCapacity: get('rate-limit-bucket-capacity'),
      rateLimitRefillPerMinute: get('rate-limit-refill-per-minute'),
      rateLimitMaxKeys: get('rate-limit-max-keys'),
      trustedProxyHops: get('trusted-proxy-hops'),
      sseHeartbeatIntervalSeconds: get('sse-heartbeat-interval-seconds'),
      corsAllowedOrigins: _parseOrigins(get('cors-allowed-origins')),
      auditRetentionDays: get('audit-retention-days'),
      authEventRetentionDays: get('auth-event-retention-days'),
      auditPurgeBatchSize: get('audit-purge-batch-size'),
      dbReadPoolSize: get('db-read-pool-size'),
    );
  }
}

/// Splits `cors-allowed-origins`'s raw comma-separated value into a set of
/// origins, trimming whitespace and dropping empty segments — so a trailing
/// comma or stray space doesn't produce a spurious entry that could never
/// match a real `Origin` header.
Set<String> _parseOrigins(String raw) => raw
    .split(',')
    .map((origin) => origin.trim())
    .where((origin) => origin.isNotEmpty)
    .toSet();
