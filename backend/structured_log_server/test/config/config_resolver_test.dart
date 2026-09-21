import 'dart:io';

import 'package:structured_log_server/src/auth/hashing.dart'
    show passwordPolicyMessage;
import 'package:structured_log_server/src/config/config_resolver.dart';
import 'package:structured_log_server/src/config/config_source.dart';
import 'package:structured_log_server/src/config/param_spec.dart';
import 'package:test/test.dart';

const _intParam = ParamSpec(
  name: 'http-port',
  type: ParamType.int,
  description: 'Port.',
  defaultValue: 8080,
);
const _stringParam = ParamSpec(
  name: 'db-path',
  type: ParamType.string,
  description: 'DB path.',
  requiredForCommands: {'serve'},
);
const _boolParam = ParamSpec(
  name: 'rate-limit-enabled',
  type: ParamType.bool,
  description: 'Rate limiting.',
  defaultValue: true,
);
const _enumParam = ParamSpec(
  name: 'log-format',
  type: ParamType.string,
  description: 'Log format.',
  defaultValue: 'console',
  allowedValues: {'console', 'json'},
);
const _secretParam = ParamSpec(
  name: 'jwt-secret',
  type: ParamType.string,
  description: 'JWT secret.',
  isSecret: true,
  requiredForCommands: {'serve'},
);

ConfigResolver resolverWith(List<ParamSpec> specs) => ConfigResolver(specs);

void main() {
  group('CLI/env/default priority', () {
    test('a CLI argument overrides an environment variable', () {
      final result = resolverWith([_intParam]).parse(
        ['--http-port=9000'],
        {'STRUCTURED_LOG_HTTP_PORT': '7000'},
        command: 'serve',
      );
      expect(result.outcome, ConfigParseOutcome.success);
      expect(result.values!['http-port']!.value, 9000);
      expect(result.values!['http-port']!.source, ConfigSource.cli);
    });

    test('an environment variable overrides the default', () {
      final result = resolverWith([
        _intParam,
      ]).parse([], {'STRUCTURED_LOG_HTTP_PORT': '7000'}, command: 'serve');
      expect(result.values!['http-port']!.value, 7000);
      expect(result.values!['http-port']!.source, ConfigSource.env);
    });

    test('an unset parameter takes its default', () {
      final result = resolverWith([_intParam]).parse([], {}, command: 'serve');
      expect(result.values!['http-port']!.value, 8080);
      expect(result.values!['http-port']!.source, ConfigSource.defaultValue);
    });

    test('an empty-string environment variable is treated as unset', () {
      final result = resolverWith([
        _intParam,
      ]).parse([], {'STRUCTURED_LOG_HTTP_PORT': ''}, command: 'serve');
      expect(result.values!['http-port']!.value, 8080);
      expect(result.values!['http-port']!.source, ConfigSource.defaultValue);
    });
  });

  group('CLI/env name correspondence', () {
    test('a non-secret param has both a CLI flag and an env var', () {
      final resolver = resolverWith([_intParam]);
      expect(resolver.usage(), contains('--http-port'));
      final viaCli = resolver.parse(['--http-port=1'], {}, command: 'serve');
      final viaEnv = resolver.parse([], {
        'STRUCTURED_LOG_HTTP_PORT': '1',
      }, command: 'serve');
      expect(viaCli.values!['http-port']!.value, 1);
      expect(viaEnv.values!['http-port']!.value, 1);
    });
  });

  group('strict typed parsing', () {
    test('a non-integer value for an int param is rejected', () {
      final result = resolverWith([
        _intParam,
      ]).parse(['--http-port=not-a-number'], {}, command: 'serve');
      expect(result.outcome, ConfigParseOutcome.errors);
      expect(result.errors.single, contains('http-port'));
    });

    test('an unrecognized boolean value is rejected, not treated as false', () {
      final result = resolverWith([_boolParam]).parse([], {
        'STRUCTURED_LOG_RATE_LIMIT_ENABLED': 'maybe',
      }, command: 'serve');
      expect(result.outcome, ConfigParseOutcome.errors);
    });

    test('true/false/1/0/yes/no are all accepted, case-insensitively', () {
      for (final accepted in ['TRUE', 'false', '1', '0', 'Yes', 'no']) {
        final result = resolverWith([_boolParam]).parse([], {
          'STRUCTURED_LOG_RATE_LIMIT_ENABLED': accepted,
        }, command: 'serve');
        expect(result.outcome, ConfigParseOutcome.success, reason: accepted);
      }
    });

    test('a value outside allowedValues is rejected', () {
      final result = resolverWith([
        _enumParam,
      ]).parse(['--log-format=yaml'], {}, command: 'serve');
      expect(result.outcome, ConfigParseOutcome.errors);
    });
  });

  group('required-by-command', () {
    test('a required param missing for its command is an error', () {
      final result = resolverWith([
        _stringParam,
      ]).parse([], {}, command: 'serve');
      expect(result.outcome, ConfigParseOutcome.errors);
    });

    test(
      'the same param is optional for a command not in requiredForCommands',
      () {
        final result = resolverWith([
          _stringParam,
        ]).parse([], {}, command: 'other-command');
        expect(result.outcome, ConfigParseOutcome.success);
      },
    );

    test('multiple simultaneous errors are all reported at once', () {
      final result = resolverWith([
        _stringParam,
        _intParam,
      ]).parse(['--http-port=nope'], {}, command: 'serve');
      expect(result.errors, hasLength(2));
    });
  });

  group('unknown parameters', () {
    test('an unknown CLI argument is rejected', () {
      final result = resolverWith([
        _intParam,
      ]).parse(['--does-not-exist=1'], {}, command: 'serve');
      expect(result.outcome, ConfigParseOutcome.errors);
    });

    test('an unknown STRUCTURED_LOG_ env var only warns, does not fail', () {
      final result = resolverWith([
        _intParam,
      ]).parse([], {'STRUCTURED_LOG_TYPO_FIELD': 'x'}, command: 'serve');
      expect(result.outcome, ConfigParseOutcome.success);
      expect(result.warnings.single, contains('STRUCTURED_LOG_TYPO_FIELD'));
    });

    test('an env var without the prefix is not warned about', () {
      final result = resolverWith([
        _intParam,
      ]).parse([], {'PATH': '/usr/bin'}, command: 'serve');
      expect(result.warnings, isEmpty);
    });
  });

  group('secrets', () {
    test('there is no CLI flag for a secret param', () {
      final result = resolverWith([
        _secretParam,
      ]).parse(['--jwt-secret=x'], {}, command: 'serve');
      expect(result.outcome, ConfigParseOutcome.errors);
      expect(result.errors.single, contains('jwt-secret'));
    });

    test('a secret is read from its env var', () {
      final result = resolverWith([
        _secretParam,
      ]).parse([], {'STRUCTURED_LOG_JWT_SECRET': 's3cr3t'}, command: 'serve');
      expect(result.values!['jwt-secret']!.value, 's3cr3t');
      expect(result.values!['jwt-secret']!.source, ConfigSource.env);
    });

    test('a secret is read from a _FILE path, trailing newline stripped', () {
      final file = File(
        '${Directory.systemTemp.createTempSync().path}/secret.txt',
      );
      file.writeAsStringSync('from-file-secret\n');
      addTearDown(() => file.parent.deleteSync(recursive: true));

      final result = resolverWith([_secretParam]).parse([], {
        'STRUCTURED_LOG_JWT_SECRET_FILE': file.path,
      }, command: 'serve');
      expect(result.values!['jwt-secret']!.value, 'from-file-secret');
      expect(result.values!['jwt-secret']!.source, ConfigSource.file);
    });

    test('setting both the value and the _FILE form is rejected', () {
      final result = resolverWith([_secretParam]).parse([], {
        'STRUCTURED_LOG_JWT_SECRET': 'a',
        'STRUCTURED_LOG_JWT_SECRET_FILE': '/tmp/whatever',
      }, command: 'serve');
      expect(result.outcome, ConfigParseOutcome.errors);
    });

    test('an unreadable secret file is rejected', () {
      final result = resolverWith([_secretParam]).parse([], {
        'STRUCTURED_LOG_JWT_SECRET_FILE': '/no/such/path',
      }, command: 'serve');
      expect(result.outcome, ConfigParseOutcome.errors);
    });

    test('a required secret missing for its command is an error', () {
      final result = resolverWith([
        _secretParam,
      ]).parse([], {}, command: 'serve');
      expect(result.outcome, ConfigParseOutcome.errors);
    });

    test('an optional secret with no default resolves to null when unset', () {
      const optionalSecret = ParamSpec(
        name: 'bootstrap-admin-password',
        type: ParamType.string,
        description: 'x',
        isSecret: true,
      );
      final result = resolverWith([
        optionalSecret,
      ]).parse([], {}, command: 'serve');
      expect(result.outcome, ConfigParseOutcome.success);
      expect(result.values!['bootstrap-admin-password']!.value, isNull);
    });
  });

  group('a secret with its own rules', () {
    const validated = ParamSpec(
      name: 'bootstrap-admin-password',
      type: ParamType.string,
      description: 'x',
      isSecret: true,
      validator: passwordPolicyMessage,
    );
    ConfigParseResult parseWith(String? value) =>
        resolverWith([validated]).parse([], {
          if (value != null) validated.envVarName: value,
        }, command: 'serve');

    test('an acceptable value resolves', () {
      final result = parseWith('long-enough-1');
      expect(result.outcome, ConfigParseOutcome.success);
      expect(
        result.values!['bootstrap-admin-password']!.value,
        'long-enough-1',
      );
    });

    test(
      'an unacceptable value is a configuration error naming the variable',
      () {
        final result = parseWith('short');
        expect(result.outcome, ConfigParseOutcome.errors);
        expect(result.errors.single, contains(validated.envVarName));
        expect(result.errors.single, contains('at least 8 characters'));
      },
    );

    test('the error never repeats the secret', () {
      final result = parseWith('hunter2');
      expect(result.errors.join(), isNot(contains('hunter2')));
    });

    test('an unset value is not checked', () {
      expect(parseWith(null).outcome, ConfigParseOutcome.success);
    });
  });

  group('--help/--version/--print-config', () {
    test(
      '--help produces text mentioning every param and does not resolve config',
      () {
        final result = resolverWith([
          _intParam,
          _stringParam,
        ]).parse(['--help'], {}, command: 'serve');
        expect(result.outcome, ConfigParseOutcome.help);
        expect(result.helpText, contains('http-port'));
        expect(result.helpText, contains('db-path'));
      },
    );

    test('--version does not resolve config', () {
      final result = resolverWith([
        _stringParam,
      ]).parse(['--version'], {}, command: 'serve');
      expect(result.outcome, ConfigParseOutcome.version);
    });

    test(
      '--print-config succeeds even though normal validation would pass',
      () {
        final result = resolverWith([
          _intParam,
        ]).parse(['--print-config'], {}, command: 'serve');
        expect(result.outcome, ConfigParseOutcome.printConfig);
      },
    );

    test('--print-config still reports errors instead of masking them', () {
      final result = resolverWith([
        _stringParam,
      ]).parse(['--print-config'], {}, command: 'serve');
      expect(result.outcome, ConfigParseOutcome.errors);
    });
  });

  group('formatPrintConfig', () {
    test('a secret value is masked but its source is shown', () {
      final result = resolverWith([_secretParam]).parse([], {
        'STRUCTURED_LOG_JWT_SECRET': 'top-secret-value',
      }, command: 'serve');
      final output = formatPrintConfig([_secretParam], result.values!);
      expect(output, isNot(contains('top-secret-value')));
      expect(output, contains('***'));
      expect(output, contains('env'));
    });

    test('a non-secret value is shown along with its source', () {
      final result = resolverWith([
        _intParam,
      ]).parse(['--http-port=1234'], {}, command: 'serve');
      final output = formatPrintConfig([_intParam], result.values!);
      expect(output, contains('1234'));
      expect(output, contains('cli'));
    });
  });
}
