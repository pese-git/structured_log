import 'package:args/args.dart';

import 'config_source.dart';
import 'param_spec.dart';
import 'secret_source.dart';

/// One resolved parameter — its typed value ([String]/[int]/[bool], or
/// `null` for an unset optional secret) and where it came from.
class ResolvedValue {
  final Object? value;
  final ConfigSource source;
  const ResolvedValue(this.value, this.source);
}

enum ConfigParseOutcome { success, printConfig, errors, help, version }

/// The outcome of [ConfigResolver.parse] — exactly one of a resolved
/// configuration, a request to print `--help`/`--version`/`--print-config`
/// and exit, or a list of every configuration error found
/// (`log-server-config`: errors are reported all at once, not one at a
/// time).
class ConfigParseResult {
  final ConfigParseOutcome outcome;
  final Map<String, ResolvedValue>? values;
  final List<String> errors;
  final List<String> warnings;
  final String? helpText;

  const ConfigParseResult._(
    this.outcome, {
    this.values,
    this.errors = const [],
    this.warnings = const [],
    this.helpText,
  });

  factory ConfigParseResult.success(
    Map<String, ResolvedValue> values, {
    List<String> warnings = const [],
  }) => ConfigParseResult._(
    ConfigParseOutcome.success,
    values: values,
    warnings: warnings,
  );

  factory ConfigParseResult.printConfig(
    Map<String, ResolvedValue> values, {
    List<String> warnings = const [],
  }) => ConfigParseResult._(
    ConfigParseOutcome.printConfig,
    values: values,
    warnings: warnings,
  );

  factory ConfigParseResult.errors(
    List<String> errors, {
    List<String> warnings = const [],
  }) => ConfigParseResult._(
    ConfigParseOutcome.errors,
    errors: errors,
    warnings: warnings,
  );

  factory ConfigParseResult.help(String helpText) =>
      ConfigParseResult._(ConfigParseOutcome.help, helpText: helpText);

  factory ConfigParseResult.version() =>
      const ConfigParseResult._(ConfigParseOutcome.version);
}

/// `EX_CONFIG` (BSD sysexits.h) — the exit code `log-server-config`
/// mandates for any configuration error, distinct from a runtime failure.
const exitCodeConfigError = 78;

/// Resolves a [ParamSpec] list against CLI arguments and the process
/// environment: CLI > env > default for ordinary params, a dedicated
/// env-or-`_FILE` path for secrets (`secret_source.dart`), strict typed
/// parsing, and validation that accumulates every error before reporting
/// (`log-server-config`). One resolver instance is shared by every
/// subcommand — [parse]'s `command` argument is only used to decide which
/// [ParamSpec.requiredForCommands] apply.
class ConfigResolver {
  final List<ParamSpec> specs;

  ConfigResolver(this.specs)
    : assert(
        specs.map((s) => s.name).toSet().length == specs.length,
        'ParamSpec names must be unique',
      );

  ArgParser _buildArgParser() {
    final parser = ArgParser()
      ..addFlag('help', abbr: 'h', negatable: false, help: 'Show this help.')
      ..addFlag('version', negatable: false, help: 'Show the version and exit.')
      ..addFlag(
        'print-config',
        negatable: false,
        help: 'Print the effective configuration and exit.',
      );
    for (final spec in specs) {
      if (spec.isSecret) continue; // secrets have no CLI flag at all
      switch (spec.type) {
        case ParamType.bool:
          parser.addFlag(spec.name, help: spec.description);
        case ParamType.int:
        case ParamType.string:
          parser.addOption(spec.name, help: spec.description);
      }
    }
    return parser;
  }

  String usage() => _buildArgParser().usage;

  ConfigParseResult parse(
    List<String> args,
    Map<String, String> env, {
    required String command,
  }) {
    final parser = _buildArgParser();
    final ArgResults results;
    try {
      results = parser.parse(args);
    } on FormatException catch (e) {
      return ConfigParseResult.errors(['Invalid arguments: ${e.message}']);
    }

    if (results.flag('help')) return ConfigParseResult.help(parser.usage);
    if (results.flag('version')) return ConfigParseResult.version();

    final errors = <String>[];
    final values = <String, ResolvedValue>{};

    for (final spec in specs) {
      if (spec.isSecret) {
        _resolveSecretParam(spec, env, command, values, errors);
      } else {
        _resolveOrdinaryParam(spec, results, env, command, values, errors);
      }
    }

    final warnings = _unknownEnvWarnings(env);

    if (errors.isNotEmpty) {
      return ConfigParseResult.errors(errors, warnings: warnings);
    }
    if (results.flag('print-config')) {
      return ConfigParseResult.printConfig(values, warnings: warnings);
    }
    return ConfigParseResult.success(values, warnings: warnings);
  }

  void _resolveSecretParam(
    ParamSpec spec,
    Map<String, String> env,
    String command,
    Map<String, ResolvedValue> values,
    List<String> errors,
  ) {
    final resolution = resolveSecret(spec, env);
    if (resolution.isError) {
      errors.add(resolution.error!);
      return;
    }
    if (resolution.isUnset) {
      if (spec.requiredForCommands.contains(command)) {
        errors.add(
          '${spec.envVarName} is required for "$command" but was not set.',
        );
      }
      values[spec.name] = ResolvedValue(
        spec.defaultValue,
        ConfigSource.defaultValue,
      );
    } else {
      final problem = spec.validator?.call(resolution.value as String);
      if (problem != null) {
        errors.add('${spec.envVarName}: $problem');
      }
      values[spec.name] = ResolvedValue(resolution.value, resolution.source!);
    }
  }

  void _resolveOrdinaryParam(
    ParamSpec spec,
    ArgResults results,
    Map<String, String> env,
    String command,
    Map<String, ResolvedValue> values,
    List<String> errors,
  ) {
    String? raw;
    ConfigSource source = ConfigSource.defaultValue;

    if (results.wasParsed(spec.name)) {
      raw = spec.type == ParamType.bool
          ? results.flag(spec.name).toString()
          : results.option(spec.name);
      source = ConfigSource.cli;
    } else {
      final envValue = env[spec.envVarName];
      if (envValue != null && envValue.isNotEmpty) {
        raw = envValue;
        source = ConfigSource.env;
      }
    }

    if (raw == null) {
      if (spec.defaultValue == null &&
          spec.requiredForCommands.contains(command)) {
        errors.add(
          '--${spec.name} (${spec.envVarName}) is required for "$command" '
          'but was not set.',
        );
      }
      values[spec.name] = ResolvedValue(
        spec.defaultValue,
        ConfigSource.defaultValue,
      );
      return;
    }

    final coerced = _coerce(spec, raw);
    if (coerced.error != null) {
      errors.add(coerced.error!);
      return;
    }
    values[spec.name] = ResolvedValue(coerced.value, source);
  }

  List<String> _unknownEnvWarnings(Map<String, String> env) {
    final known = <String>{
      for (final spec in specs) spec.envVarName,
      for (final spec in specs.where((s) => s.isSecret))
        '${spec.envVarName}_FILE',
    };
    return [
      for (final key in env.keys)
        if (key.startsWith('STRUCTURED_LOG_') && !known.contains(key))
          'Unrecognized environment variable: $key (ignored)',
    ];
  }
}

class _Coerced {
  final Object? value;
  final String? error;
  const _Coerced.ok(this.value) : error = null;
  const _Coerced.err(this.error) : value = null;
}

_Coerced _coerce(ParamSpec spec, String raw) {
  switch (spec.type) {
    case ParamType.string:
      if (spec.allowedValues != null && !spec.allowedValues!.contains(raw)) {
        return _Coerced.err(
          '${spec.name}: must be one of ${spec.allowedValues!.join(', ')}, '
          'got "$raw"',
        );
      }
      return _Coerced.ok(raw);
    case ParamType.int:
      final parsed = int.tryParse(raw);
      if (parsed == null) {
        return _Coerced.err('${spec.name}: must be an integer, got "$raw"');
      }
      if (spec.mustBePositive && parsed < 1) {
        return _Coerced.err('${spec.name}: must be at least 1, got "$raw"');
      }
      final min = spec.minValue, max = spec.maxValue;
      if ((min != null && parsed < min) || (max != null && parsed > max)) {
        final range = min != null && max != null
            ? 'between $min and $max'
            : min != null
            ? 'at least $min'
            : 'at most $max';
        return _Coerced.err('${spec.name}: must be $range, got "$raw"');
      }
      return _Coerced.ok(parsed);
    case ParamType.bool:
      final normalized = raw.toLowerCase();
      if (const ['true', '1', 'yes'].contains(normalized)) {
        return const _Coerced.ok(true);
      }
      if (const ['false', '0', 'no'].contains(normalized)) {
        return const _Coerced.ok(false);
      }
      return _Coerced.err(
        '${spec.name}: must be one of true/false/1/0/yes/no, got "$raw"',
      );
  }
}

/// Renders resolved [values] for `--print-config` — every non-secret value
/// with its source, secrets masked to a placeholder that still names the
/// source (`log-server-config`).
String formatPrintConfig(
  List<ParamSpec> specs,
  Map<String, ResolvedValue> values,
) {
  final buffer = StringBuffer();
  for (final spec in specs) {
    final resolved = values[spec.name];
    if (resolved == null) continue;
    final display = spec.isSecret
        ? (resolved.value == null ? '(unset)' : '*** (${resolved.source.name})')
        : '${resolved.value} (${resolved.source.name})';
    buffer.writeln('${spec.name}: $display');
  }
  return buffer.toString();
}
