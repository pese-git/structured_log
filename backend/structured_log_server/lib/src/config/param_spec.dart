/// How a configuration parameter's value is typed and parsed
/// (`log-server-config`). Kept deliberately small — every Stage 1 field
/// fits `string`/`int`/`bool`; a wider type would need a new case here.
enum ParamType { string, int, bool }

/// One configuration parameter's full declaration — name, type, default,
/// and whether it's a secret. A single [ParamSpec] list is the one source
/// [ConfigResolver] builds the CLI parser, env var names, and `--help`
/// text from, so they can't drift apart (`log-server-config`: "справка
/// порождена из тех же описаний параметров, что используются при
/// разборе").
///
/// Non-secret params get both a `--kebab-case` CLI flag and a
/// `STRUCTURED_LOG_KEBAB_CASE` env var, mechanically derived from [name].
/// Secret params ([isSecret]) get no CLI flag at all — only the env var and
/// its `_FILE` sibling (`SecretSource`).
class ParamSpec {
  /// kebab-case, e.g. `http-port`. The env var name is derived from this:
  /// `STRUCTURED_LOG_` + this name uppercased with `-` replaced by `_`.
  final String name;
  final ParamType type;
  final String description;

  /// `null` means "no default" — the param is either required (see
  /// [requiredForCommands]) or intentionally optional-with-no-fallback
  /// (e.g. `bootstrapAdminPassword`, which means "generate one" when unset,
  /// not "use this literal default").
  final Object? defaultValue;

  final bool isSecret;

  /// Commands for which a missing value (no CLI/env, no [defaultValue]) is
  /// a configuration error. A command not in this set treats a missing
  /// value as simply absent — read by whatever code path only needs it
  /// conditionally (`log-server-config`: "набор обязательных параметров
  /// зависит от выполняемой команды").
  final Set<String> requiredForCommands;

  /// For a string param with a closed set of valid values (e.g.
  /// `logLevel`, `logFormat`) — any other value is a config error.
  final Set<String>? allowedValues;

  /// For an int param where zero and negatives are meaningless rather than
  /// merely unusual — a retention of `0` days, or a purge chunk of `0`, is a
  /// setting that either deletes everything or never terminates. Refused at
  /// startup with the rest of the configuration, because a server that took
  /// it and then behaved strangely is far harder to diagnose than one that
  /// would not start (`log-server-config`: the whole configuration is checked
  /// before the port opens).
  final bool mustBePositive;

  /// For an int param whose valid range includes zero but is still bounded —
  /// inclusive limits, either may be omitted. Checked with the rest of the
  /// configuration, like [mustBePositive].
  final int? minValue;
  final int? maxValue;

  /// For a secret whose value has rules of its own: returns what is wrong with
  /// it, or `null`. The message is reported with the rest of the configuration
  /// errors and must not repeat the value — it is a secret, and startup output
  /// goes to logs.
  final String? Function(String value)? validator;

  const ParamSpec({
    required this.name,
    required this.type,
    required this.description,
    this.defaultValue,
    this.isSecret = false,
    this.requiredForCommands = const {},
    this.allowedValues,
    this.mustBePositive = false,
    this.minValue,
    this.maxValue,
    this.validator,
  });

  String get envVarName =>
      'STRUCTURED_LOG_${name.toUpperCase().replaceAll('-', '_')}';
}
