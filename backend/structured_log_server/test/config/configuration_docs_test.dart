import 'dart:io';

import 'package:structured_log_server/src/config/param_spec.dart';
import 'package:structured_log_server/src/config/server_config.dart';
import 'package:test/test.dart';

/// Keeps the operator-facing configuration docs from drifting away from
/// [serverConfigParams].
///
/// The failure this guards against is silent and lands entirely on the
/// operator: a flag is renamed in the declaration, every test still passes
/// because nothing in the code reads the old name, and the documented
/// command answers `Could not find an option named ...` and exits 78. The
/// docs are the only place that spelling is published, so nothing else can
/// catch it — the same reason `route_auth_matrix_test.dart` writes every
/// route down rather than trusting each handler to remember its `require*`
/// call. It is not hypothetical: `create-admin` was documented with
/// `--username`/`--password`, which the parser never had, on three pages at
/// once.
///
/// Scope is the reference tables, marked in the markdown with
/// `<!-- config-reference:implemented -->`, because that is what an operator
/// copies from. Prose that names a flag in passing is not policed: prose
/// that is wrong costs a reader a moment, a wrong table row costs them a
/// failed deployment.
///
/// Two directions, both fail-closed:
///
/// - every flag and `STRUCTURED_LOG_*` variable in a marked table exists in
///   [serverConfigParams];
/// - every parameter in [serverConfigParams] appears in the full reference
///   ([_fullReferenceDocs]), so a new setting cannot ship undocumented.
///
/// Settings that are planned but unbuilt are outside this — the reference
/// gives them `*(no flag)*` rather than a name, so there is no spelling to
/// check and nothing for an operator to copy. Should the tables ever start
/// publishing future flag names, they need a rule of their own: that each
/// is still absent from [serverConfigParams], so that "not implemented"
/// cannot outlive the feature.

/// Package-relative paths. `dart test` runs with the package directory as
/// the working directory, which is also how `melos run test` invokes it.
const _readmeDocs = ['README.md', 'README.ru.md'];
const _fullReferenceDocs = [
  '../../docs/operations/configuration.md',
  '../../docs/operations/configuration.ru.md',
];

final _flagPattern = RegExp(r'--[a-z0-9][a-z0-9-]*\*?');
final _envVarPattern = RegExp(r'STRUCTURED_LOG_[A-Z0-9_]+');

/// The lines of every `<!-- config-reference:[kind] -->` …
/// `<!-- /config-reference -->` block in [path], concatenated.
///
/// Returns an empty list when the file marks no such block — callers assert
/// on that rather than passing vacuously, since a deleted marker would
/// otherwise turn this whole test into a no-op.
List<String> _markedRegion(String path, String kind) {
  final open = '<!-- config-reference:$kind -->';
  const close = '<!-- /config-reference -->';
  final collected = <String>[];
  var inside = false;
  for (final line in File(path).readAsLinesSync()) {
    final trimmed = line.trim();
    if (trimmed == open) {
      inside = true;
    } else if (trimmed == close) {
      inside = false;
    } else if (inside && !trimmed.startsWith('<!--')) {
      collected.add(line);
    }
  }
  return collected;
}

/// Every flag token in [lines], with the `no-` of a negated boolean flag
/// stripped — `--no-rate-limit-enabled` documents `rate-limit-enabled`.
Set<String> _flagsIn(Iterable<String> lines, Set<String> boolParams) {
  final found = <String>{};
  for (final line in lines) {
    for (final match in _flagPattern.allMatches(line)) {
      final token = match[0]!.substring(2);
      final negated = token.startsWith('no-') ? token.substring(3) : null;
      found.add(
        negated != null && boolParams.contains(negated) ? negated : token,
      );
    }
  }
  return found;
}

Set<String> _envVarsIn(Iterable<String> lines) => {
  for (final line in lines)
    for (final match in _envVarPattern.allMatches(line)) match[0]!,
};

void main() {
  final declared = {for (final s in serverConfigParams) s.name};
  final boolParams = {
    for (final s in serverConfigParams)
      if (s.type == ParamType.bool) s.name,
  };
  final envVarToParam = {
    for (final s in serverConfigParams) s.envVarName: s.name,
  };
  final allDocs = [..._readmeDocs, ..._fullReferenceDocs];

  group('reference tables', () {
    for (final path in allDocs) {
      test('$path documents only flags that exist', () {
        final region = _markedRegion(path, 'implemented');
        expect(
          region,
          isNotEmpty,
          reason:
              '$path has no <!-- config-reference:implemented --> block. '
              'Without it this test silently checks nothing.',
        );

        final unknown = <String>[];
        for (final flag in _flagsIn(region, boolParams)) {
          // A trailing `*` abbreviates a family of flags (the README's
          // `--rate-limit-*`): it holds as long as at least one real
          // parameter still starts that way.
          if (flag.endsWith('*')) {
            final prefix = flag.substring(0, flag.length - 1);
            if (!declared.any((name) => name.startsWith(prefix))) {
              unknown.add('--$flag (matches no parameter)');
            }
            continue;
          }
          if (!declared.contains(flag)) unknown.add('--$flag');
        }

        expect(
          unknown,
          isEmpty,
          reason:
              'documented in $path but not declared in serverConfigParams — '
              'an operator copying these gets "Could not find an option '
              'named ...". Either correct the row, or give the setting a '
              '*(no flag)* row if it is not built yet.',
        );
      });

      test('$path names only environment variables that exist', () {
        final region = _markedRegion(path, 'implemented');
        final unknown = _envVarsIn(
          region,
        ).where((name) => !envVarToParam.containsKey(name)).toList();
        expect(
          unknown,
          isEmpty,
          reason:
              'documented in $path but not declared in serverConfigParams. '
              'An unrecognized STRUCTURED_LOG_* variable is simply ignored, '
              'so this drift is even quieter than a bad flag: the setting '
              'appears to be applied and is not.',
        );
      });

      test('$path never presents a secret as a CLI flag', () {
        final secrets = {
          for (final s in serverConfigParams)
            if (s.isSecret) s.name,
        };
        final region = _markedRegion(path, 'implemented');
        final leaked = _flagsIn(
          region,
          boolParams,
        ).where(secrets.contains).toList();
        expect(
          leaked,
          isEmpty,
          reason:
              'secrets get no CLI flag at all (ConfigResolver skips them '
              'when building the parser) — documenting one as a flag invites '
              'an operator to put a secret in the process listing, which is '
              'the thing decision 47 exists to prevent.',
        );
      });
    }
  });

  group('full reference completeness', () {
    for (final path in _fullReferenceDocs) {
      test('$path documents every parameter', () {
        final region = _markedRegion(path, 'implemented');
        final documented = <String>{
          ..._flagsIn(region, boolParams),
          for (final name in _envVarsIn(region))
            if (envVarToParam.containsKey(name)) envVarToParam[name]!,
        };
        expect(
          declared.difference(documented),
          isEmpty,
          reason:
              'declared in serverConfigParams but missing from $path, which '
              'is the page that claims to list all of them.',
        );
      });
    }
  });

  group('translations stay in sync', () {
    // Prose is the translator's; the set of flag names is not, and a row
    // added to one language only is exactly how the two pages start
    // describing different servers.
    test('both configuration.md translations list the same flags', () {
      final [english, russian] = _fullReferenceDocs;
      expect(
        _flagsIn(_markedRegion(russian, 'implemented'), boolParams),
        _flagsIn(_markedRegion(english, 'implemented'), boolParams),
      );
    });

    test('both README translations list the same flags', () {
      final [english, russian] = _readmeDocs;
      expect(
        _flagsIn(_markedRegion(russian, 'implemented'), boolParams),
        _flagsIn(_markedRegion(english, 'implemented'), boolParams),
      );
    });
  });
}
