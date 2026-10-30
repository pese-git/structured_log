import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// Cross-file consistency of the monorepo.
///
/// Adding a package to `emb/` touches some twenty places by hand, and the
/// ones that fail silently — a README that was not given the new line, a
/// counter written in words, a package missing from a `melos` scope — used
/// to be found by whoever added the next package. The list of packages is
/// read from the disk here, and everything else is checked against it. The
/// steps themselves are in the checklist "Новый пакет `emb/`" of `AGENTS.md`.
///
/// Runs from the repository root, like `dart test` in the `tools` CI job.

/// `structured_log_http` is the deprecated shim left behind by the rename to
/// `structured_log_remote_sync`: it has no code, no coverage floor and no place
/// in the "Related packages" sections.
const shim = 'structured_log_http';

/// How the family splits for the "one of N adapters" sentence; a package that
/// is none of these is an adapter, so a new adapter needs no edit here.
const coreName = 'structured_log';
const viewerNames = {
  'structured_log_flutter',
  'structured_log_material',
  'structured_log_fluent',
  'structured_log_cupertino',
};
const deliveryNames = {'structured_log_remote_sync'};

class Pkg {
  final String name;
  final YamlMap pubspec;

  Pkg(this.name, this.pubspec);

  String get dir => 'emb/$name';

  bool get isShim => name == shim;

  bool get isAdapter =>
      name != coreName &&
      !viewerNames.contains(name) &&
      !deliveryNames.contains(name);

  /// A Flutter package depends on the SDK; a pure Dart one does not.
  bool get isFlutter {
    final flutter = (pubspec['dependencies'] as YamlMap?)?['flutter'];
    return flutter is YamlMap && flutter['sdk'] == 'flutter';
  }
}

late final List<Pkg> emb;

/// The packages that have a README, a floor and a place in the family.
List<Pkg> get family => [
      for (final p in emb)
        if (!p.isShim) p,
    ];

List<Pkg> get adapters => [
      for (final p in family)
        if (p.isAdapter) p,
    ];

String read(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    fail('$path does not exist (the tests must run from the repository root)');
  }
  return file.readAsStringSync();
}

dynamic readYaml(String path) => loadYaml(read(path));

/// Fails with one line per violation, so a single run lists everything.
void expectNone(Iterable<String> violations, String hint) {
  if (violations.isEmpty) return;
  fail('$hint\n${violations.map((v) => '  - $v').join('\n')}');
}

/// A number the way `AGENTS.md` and the READMEs write it: in words or, when
/// the word form would need declension, in digits.
String? ruNominative(int n) {
  const units = [
    '',
    'один',
    'два',
    'три',
    'четыре',
    'пять',
    'шесть',
    'семь',
    'восемь',
    'девять',
  ];
  const teens = [
    'десять',
    'одиннадцать',
    'двенадцать',
    'тринадцать',
    'четырнадцать',
    'пятнадцать',
    'шестнадцать',
    'семнадцать',
    'восемнадцать',
    'девятнадцать',
  ];
  const tens = {20: 'двадцать', 30: 'тридцать', 40: 'сорок'};
  if (n < 5 || n > 49) return null;
  if (n < 10) return units[n];
  if (n < 20) return teens[n - 10];
  final unit = n % 10;
  // «двадцать один пакет», «двадцать две джобы»: the noun changes too.
  if (unit >= 1 && unit <= 4) return null;
  return unit == 0 ? tens[n] : '${tens[n - unit]} ${units[unit]}';
}

const _enWords = {
  6: 'six',
  7: 'seven',
  8: 'eight',
  9: 'nine',
  10: 'ten',
  11: 'eleven',
  12: 'twelve',
  13: 'thirteen',
  14: 'fourteen',
  15: 'fifteen',
  16: 'sixteen',
  17: 'seventeen',
  18: 'eighteen',
  19: 'nineteen',
  20: 'twenty',
};

const _ruGenitive = {
  6: 'шести',
  7: 'семи',
  8: 'восьми',
  9: 'девяти',
  10: 'десяти',
  11: 'одиннадцати',
  12: 'двенадцати',
  13: 'тринадцати',
  14: 'четырнадцати',
  15: 'пятнадцати',
  16: 'шестнадцати',
  17: 'семнадцати',
  18: 'восемнадцати',
  19: 'девятнадцати',
  20: 'двадцати',
};

/// Whether [written] (a word or digits, any case) says [expected].
bool says(String written, int expected, String? word) {
  final text = written.toLowerCase();
  return text == '$expected' || (word != null && text == word);
}

/// The text of a README between its "Related packages" heading and the
/// licence, or `null` without the heading.
String? relatedSection(String readme, {required bool ru}) {
  final start = readme.indexOf(
    ru ? '## Связанные пакеты' : '## Related packages',
  );
  if (start < 0) return null;
  final end = readme.indexOf(ru ? '## Лицензия' : '## License', start);
  return readme.substring(start, end < 0 ? readme.length : end);
}

final _pubDevLink = RegExp(r'\]\(https://pub\.dev/packages/([a-z0-9_]+)\)');

bool mentions(String text, String name) => RegExp('\\b$name\\b').hasMatch(text);

void main() {
  setUpAll(() {
    final dirs = Directory('emb').listSync().whereType<Directory>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    emb = [
      for (final dir in dirs)
        if (File('${dir.path}/pubspec.yaml').existsSync())
          Pkg(
            dir.uri.pathSegments.where((s) => s.isNotEmpty).last,
            readYaml('${dir.path}/pubspec.yaml') as YamlMap,
          ),
    ];
  });

  test('the disk has the packages the rest of the tests rely on', () {
    expect(emb.map((p) => p.name), contains(coreName));
    expect(
      emb.map((p) => p.name),
      contains(shim),
      reason: 'the shim is excluded by name; rename `shim` if it was removed',
    );
    expectNone([
      for (final p in emb)
        if (p.pubspec['name'] != p.name)
          '${p.dir}: pubspec says name `${p.pubspec['name']}`',
    ], 'A package directory is named after its package');
  });

  group('workspace', () {
    test(
      'every package in emb/ is listed in melos.yaml and every path exists',
      () {
        final melos = readYaml('melos.yaml') as YamlMap;
        final listed = (melos['packages'] as YamlList).cast<String>().toSet();
        expectNone([
          for (final p in emb)
            if (!listed.contains(p.dir)) '${p.dir} is not in `packages:`',
          for (final path in listed)
            if (!Directory(path).existsSync()) '$path is listed but missing',
        ], 'melos.yaml and emb/ disagree (checklist, step 4)');
      },
    );

    test('every package is in the test scope that matches its kind', () {
      final scripts = (readYaml('melos.yaml') as YamlMap)['scripts'] as YamlMap;
      Set<String> scope(String script) =>
          (((scripts[script] as YamlMap)['packageFilters'] as YamlMap)['scope']
                  as YamlList)
              .cast<String>()
              .toSet();
      final dart = scope('test:dart');
      final flutter = scope('test:flutter');
      expectNone([
        for (final p in emb)
          if (p.isFlutter && !flutter.contains(p.name))
            '${p.name} is a Flutter package and is not in `test:flutter`'
          else if (!p.isFlutter && !dart.contains(p.name))
            '${p.name} is a Dart package and is not in `test:dart`'
          else if (p.isFlutter && dart.contains(p.name))
            '${p.name} is a Flutter package but is also in `test:dart`'
          else if (!p.isFlutter && flutter.contains(p.name))
            '${p.name} is a Dart package but is also in `test:flutter`',
      ], 'A package runs under exactly one test script (checklist, step 4)');
    });
  });

  group('coverage floors', () {
    late Map<String, dynamic> floors;

    setUpAll(() {
      floors = {
        for (final e
            in (readYaml('tool/coverage_floors.json') as YamlMap).entries)
          e.key as String: e.value,
      };
    });

    test('every family package has a floor', () {
      expectNone([
        for (final p in family)
          if (floors[p.name] is! num) p.name,
      ], 'No floor in tool/coverage_floors.json (checklist, step 5)');
    });

    test('no floor names a package that does not exist', () {
      final names = <String>{};
      for (final path
          in (readYaml('melos.yaml') as YamlMap)['packages'] as YamlList) {
        final pubspec = File('$path/pubspec.yaml');
        if (pubspec.existsSync()) {
          names.add(
            (loadYaml(pubspec.readAsStringSync()) as YamlMap)['name'] as String,
          );
        }
      }
      expectNone([
        for (final key in floors.keys)
          if (!key.startsWith('_') && !names.contains(key)) key,
      ], 'A floor for a package that is gone');
    });
  });

  group('CI', () {
    test('ci.yml runs every package', () {
      final ci = read('.github/workflows/ci.yml');
      expectNone(
        [
          for (final p in emb)
            if (!ci.contains(p.dir)) p.dir,
        ],
        'No job or matrix row of ci.yml mentions the package (checklist, step 5)',
      );
    });

    test('AGENTS.md says how many jobs ci.yml has', () {
      final jobs =
          ((readYaml('.github/workflows/ci.yml') as YamlMap)['jobs'] as YamlMap)
              .length;
      final match = RegExp(r'(\S+)\s+джоб:').firstMatch(read('AGENTS.md'));
      expect(match, isNotNull, reason: 'AGENTS.md lost its "N джоб:" sentence');
      expect(
        says(match!.group(1)!, jobs, ruNominative(jobs)),
        isTrue,
        reason: 'AGENTS.md says "${match.group(1)} джоб" and ci.yml has $jobs '
            '(checklist, step 10)',
      );
    });
  });

  group('pubspec of a family package', () {
    test('has the metadata pub.dev shows', () {
      final violations = <String>[];
      for (final p in family) {
        final y = p.pubspec;
        for (final key in [
          'version',
          'homepage',
          'documentation',
          'repository',
        ]) {
          if ('${y[key] ?? ''}'.isEmpty) violations.add('${p.name}: no `$key`');
        }
        final description =
            '${y['description'] ?? ''}'.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (description.length < 60 || description.length > 180) {
          violations.add(
            '${p.name}: description is ${description.length} characters, pub.dev wants 60-180',
          );
        }
        final topics =
            (y['topics'] as YamlList?)?.cast<String>() ?? const <String>[];
        if (topics.isEmpty || topics.length > 5) {
          violations.add(
            '${p.name}: ${topics.length} topics, pub.dev takes 1-5',
          );
        }
        for (final t in topics) {
          if (!RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$').hasMatch(t) ||
              t.length < 2 ||
              t.length > 32) {
            violations.add(
              '${p.name}: topic `$t` is not 2-32 lowercase characters with hyphens',
            );
          }
        }
        if (y.containsKey('resolution')) {
          violations.add(
            '${p.name}: `resolution:` — packages are tied by melos bootstrap, not a pub workspace',
          );
        }
        if (y.containsKey('publish_to'))
          violations.add('${p.name}: `publish_to` on a published package');
      }
      expectNone(violations, 'pubspec.yaml (checklist, step 2)');
    });

    test('adapters take exactly one foreign dependency', () {
      expectNone(
        [
          for (final p in adapters)
            () {
              final foreign = [
                for (final d in (p.pubspec['dependencies'] as YamlMap).keys)
                  if (d != 'structured_log' && d != 'flutter') d,
              ];
              return foreign.length == 1 ? null : '${p.name}: $foreign';
            }(),
        ].nonNulls,
        'An adapter depends on structured_log and exactly one library',
      );
    });

    test('the core depends on nothing but meta', () {
      final deps = (emb
                  .firstWhere((p) => p.name == coreName)
                  .pubspec['dependencies'] as YamlMap?)
              ?.keys
              .cast<String>()
              .toSet() ??
          <String>{};
      expect(deps.difference({'meta'}), isEmpty);
    });
  });

  group('notes in the directory', () {
    test('every package has AGENTS.md, a CLAUDE.md link and a .pubignore', () {
      final violations = <String>[];
      for (final p in emb) {
        if (!File('${p.dir}/AGENTS.md').existsSync())
          violations.add('${p.dir}: no AGENTS.md');
        final claude = '${p.dir}/CLAUDE.md';
        final isLink = Link(claude).existsSync() &&
            Link(claude).targetSync() == 'AGENTS.md';
        // Windows without symlink support checks a link out as a file that
        // holds the target path.
        final isPlaceholder = File(claude).existsSync() &&
            File(claude).readAsStringSync().trim() == 'AGENTS.md';
        if (!isLink && !isPlaceholder)
          violations.add('$claude is not a link to AGENTS.md');
        final pubignore = File('${p.dir}/.pubignore');
        final lines = pubignore.existsSync()
            ? pubignore.readAsLinesSync().map((l) => l.trim()).toSet()
            : <String>{};
        for (final name in ['AGENTS.md', 'CLAUDE.md']) {
          if (!lines.contains(name))
            violations.add(
              '${p.dir}/.pubignore does not list $name, so it would reach pub.dev',
            );
        }
      }
      expectNone(violations, 'Notes of the directory (checklist, step 3)');
    });

    test('the other applications keep theirs as well', () {
      const dirs = [
        'backend/structured_log_server',
        'frontend/structured_log_admin_client',
        'frontend/structured_log_admin_ui',
        'packages/e2e',
        'deploy',
      ];
      expectNone([
        for (final d in dirs)
          if (!File('$d/AGENTS.md').existsSync()) '$d/AGENTS.md',
      ], 'AGENTS.md of a directory is missing');
    });
  });

  group('README family', () {
    test('both languages exist and list every other family package', () {
      final violations = <String>[];
      for (final p in family) {
        for (final ru in [false, true]) {
          final path = '${p.dir}/${ru ? 'README.ru.md' : 'README.md'}';
          if (!File(path).existsSync()) {
            violations.add('$path does not exist');
            continue;
          }
          final section = relatedSection(read(path), ru: ru);
          if (section == null) {
            violations.add(
              '$path has no "${ru ? 'Связанные пакеты' : 'Related packages'}" section',
            );
            continue;
          }
          final listed =
              _pubDevLink.allMatches(section).map((m) => m.group(1)!).toSet();
          final expected = {
            for (final q in family)
              if (q.name != p.name) q.name,
          };
          for (final name in expected.difference(listed)) {
            violations.add('$path does not list $name');
          }
          for (final name in listed.difference(expected)) {
            violations.add(
              '$path lists $name, which is itself, the shim or unknown',
            );
          }
        }
      }
      expectNone(
        violations,
        'Related packages (checklist, step 6); the lines are absolute pub.dev links',
      );
    });

    test('"one of N adapters" counts the adapters', () {
      final n = adapters.length;
      final violations = <String>[];
      for (final p in family) {
        for (final ru in [false, true]) {
          final path = '${p.dir}/${ru ? 'README.ru.md' : 'README.md'}';
          if (!File(path).existsSync()) continue;
          final match = (ru
                  ? RegExp(r'Это один из (\S+) адаптеров')
                  : RegExp(r'It is one of (\S+) adapters'))
              .firstMatch(read(path));
          if (match == null) continue;
          if (!says(match.group(1)!, n, ru ? _ruGenitive[n] : _enWords[n])) {
            violations.add(
              '$path says "${match.group(1)}", there are $n adapters',
            );
          }
        }
      }
      expectNone(
        violations,
        'The adapter count in the README (checklist, step 6)',
      );
    });
  });

  group('root documents', () {
    test(
      'the root READMEs, the guide and the site name every family package',
      () {
        final documents = {
          'README.md': read('README.md'),
          'README.ru.md': read('README.ru.md'),
          'docs/guides/embedding-guide.md': read(
            'docs/guides/embedding-guide.md',
          ),
          'docs/guides/embedding-guide.ru.md': read(
            'docs/guides/embedding-guide.ru.md',
          ),
        };
        expectNone([
          for (final p in family)
            for (final e in documents.entries)
              if (!mentions(e.value, p.name))
                '${e.key} does not mention ${p.name}',
        ], 'A package is missing from a root document (checklist, steps 7-8)');
      },
    );

    test('the site links the page of every family package', () {
      final pages = {
        'site/src/content/docs/index.mdx': '/packages/',
        'site/src/content/docs/ru/index.mdx': '/packages/',
        'site/src/content/docs/packages/index.md': '/packages/',
        'site/src/content/docs/ru/packages/index.md': '/packages/',
      };
      expectNone([
        for (final p in family)
          for (final e in pages.entries)
            if (!read(e.key).contains('${e.value}${p.name}/'))
              '${e.key} has no link to ${e.value}${p.name}/',
      ], 'The landing page or the table of packages (checklist, step 9)');
    });

    test('AGENTS.md counts the packages and points to their notes', () {
      final agents = read('AGENTS.md');
      final count = RegExp(r'(\S+)\s+пакетов\s+в\s+`emb/`\s+—\s+(\S+)\s+живых')
          .firstMatch(agents);
      expect(
        count,
        isNotNull,
        reason: 'AGENTS.md lost its "N пакетов в emb/" sentence',
      );
      expect(
        says(count!.group(1)!, emb.length, ruNominative(emb.length)),
        isTrue,
        reason:
            'AGENTS.md says "${count.group(1)}" packages in emb/, the disk has ${emb.length} (checklist, step 10)',
      );
      expect(
        says(count.group(2)!, family.length, ruNominative(family.length)),
        isTrue,
        reason:
            'AGENTS.md says "${count.group(2)}" live, the disk has ${family.length} (checklist, step 10)',
      );

      final rule =
          RegExp(r'\((\d+)\s+файл\S*\s+на\s+(\d+)\s+пакет').firstMatch(agents);
      expect(
        rule,
        isNotNull,
        reason: 'AGENTS.md lost the "N файлов на M пакетов" rule',
      );
      expect(
        [int.parse(rule!.group(1)!), int.parse(rule.group(2)!)],
        [family.length * 2, family.length],
        reason:
            'The Related packages rule counts the READMEs of the existing packages (checklist, step 10)',
      );

      expectNone([
        for (final p in emb)
          if (!agents.contains('(${p.dir}/AGENTS.md)'))
            '${p.name}: no link to ${p.dir}/AGENTS.md',
        for (final p in emb)
          if (!agents.contains('[${p.dir}/](${p.dir}/)'))
            '${p.name}: not in the list of the repository',
      ], 'AGENTS.md does not mention a package (checklist, step 10)');
    });
  });
}
