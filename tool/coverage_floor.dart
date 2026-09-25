/// Checks one package's line coverage against the floor recorded for it in
/// `tool/coverage_floors.json`, and prints the number either way.
///
/// Run by every CI job that has a test suite:
///
/// ```
/// dart run tool/coverage_floor.dart --package structured_log \
///   --lcov emb/structured_log/coverage/lcov.info
/// ```
///
/// A floor rather than a target, and per package rather than one number for
/// the repository: the packages differ by an order of magnitude in what a
/// percent even means — a widget kit is nearly all branchless build methods,
/// a server is not — and one repository-wide number would be met by the
/// packages that need it least.
///
/// The floors are set a little below what each package measures today, so
/// that ordinary work does not redden the build on noise; they are meant to
/// be raised when a package earns it, never lowered to make a build pass.
library;

import 'dart:convert';
import 'dart:io';

/// Whether [path] names a file somebody generated rather than wrote.
///
/// Three shapes, and the third is the one worth remembering: `gen-l10n`
/// output is **committed** (`l10n.yaml`, not a synthetic package), so it
/// does not end in `.g.dart` and would otherwise be counted as code a human
/// is expected to test — 503 lines of it in the admin client alone, which
/// moves that package's number by six points on its own.
bool isGenerated(String path) {
  final name = path.split('/').last;
  return name.endsWith('.g.dart') ||
      name.endsWith('.freezed.dart') ||
      name.startsWith('app_localizations');
}

/// Line coverage of the files a human wrote.
class CoverageReport {
  final int hit;
  final int total;

  /// `path` → (hit, total), for naming the weakest files when the floor is
  /// missed. Ordered as the report was read.
  final Map<String, ({int hit, int total})> byFile;

  const CoverageReport({
    required this.hit,
    required this.total,
    required this.byFile,
  });

  double get percent => total == 0 ? 0 : 100 * hit / total;

  /// Whether this clears [floor] percent.
  ///
  /// An empty report never clears it, whatever the floor: no data means the
  /// step that should have produced it did not run, and a gate that reads
  /// silence as success is worse than no gate.
  bool meets(num floor) => total > 0 && percent >= floor;
}

/// Reads `format_coverage --lcov` output, ignoring generated files.
///
/// A file may appear more than once — the server collects three test runs
/// into one directory — so hits are merged per line: covered by any run is
/// covered.
CoverageReport parseLcov(Iterable<String> lines) {
  final hits = <String, Map<int, int>>{};
  var current = '';

  for (final line in lines) {
    if (line.startsWith('SF:')) {
      current = line.substring(3).trim();
      if (!isGenerated(current)) hits.putIfAbsent(current, () => {});
    } else if (line.startsWith('DA:') && hits.containsKey(current)) {
      final parts = line.substring(3).trim().split(',');
      if (parts.length < 2) continue;
      final number = int.tryParse(parts[0]);
      final count = int.tryParse(parts[1]);
      if (number == null || count == null) continue;
      hits[current]![number] = (hits[current]![number] ?? 0) + count;
    }
  }

  var hit = 0;
  var total = 0;
  final byFile = <String, ({int hit, int total})>{};
  for (final entry in hits.entries) {
    final covered = entry.value.values.where((count) => count > 0).length;
    byFile[entry.key] = (hit: covered, total: entry.value.length);
    hit += covered;
    total += entry.value.length;
  }

  return CoverageReport(hit: hit, total: total, byFile: byFile);
}

Future<void> main(List<String> args) async {
  final options = _parse(args);
  final package = options['package'];
  final lcovPath = options['lcov'];
  if (package == null || lcovPath == null) {
    stderr.writeln(
      'usage: dart run tool/coverage_floor.dart --package <name> '
      '--lcov <path to lcov.info>',
    );
    exit(64);
  }

  final floors =
      jsonDecode(File('tool/coverage_floors.json').readAsStringSync())
          as Map<String, dynamic>;
  final floor = floors[package];
  if (floor is! num) {
    stderr.writeln(
      'No floor recorded for "$package" in tool/coverage_floors.json. Add '
      'one — a package whose coverage nobody decided on is a package this '
      'gate cannot speak for.',
    );
    exit(64);
  }

  final file = File(lcovPath);
  if (!file.existsSync()) {
    stderr.writeln('No coverage at $lcovPath — did the test step run?');
    exit(1);
  }

  final report = parseLcov(file.readAsLinesSync());
  final measured = report.percent.toStringAsFixed(1);
  final passed = report.meets(floor);

  stdout.writeln(
    '$package: $measured% of ${report.total} lines '
    '(floor $floor%) — ${passed ? 'ok' : 'BELOW FLOOR'}',
  );
  _summarize(package, report, floor, passed);

  if (!passed) {
    final weakest = report.byFile.entries.toList()
      ..sort((a, b) => (a.value.hit / a.value.total).compareTo(
            b.value.hit / b.value.total,
          ));
    stderr.writeln('Least covered files:');
    for (final entry in weakest.take(5)) {
      final share = 100 * entry.value.hit / entry.value.total;
      stderr.writeln(
        '  ${share.toStringAsFixed(1)}%  ${entry.value.hit}/'
        '${entry.value.total}  ${entry.key}',
      );
    }
    exit(1);
  }
}

/// Appends a row to the GitHub job summary when running there, so the number
/// is visible without opening the log.
void _summarize(
  String package,
  CoverageReport report,
  num floor,
  bool passed,
) {
  final path = Platform.environment['GITHUB_STEP_SUMMARY'];
  if (path == null) return;
  File(path).writeAsStringSync(
    '| `$package` | ${report.percent.toStringAsFixed(1)}% | $floor% | '
    '${passed ? 'ok' : '**below floor**'} |\n',
    mode: FileMode.append,
  );
}

Map<String, String> _parse(List<String> args) {
  final parsed = <String, String>{};
  for (var i = 0; i < args.length - 1; i++) {
    if (args[i].startsWith('--')) parsed[args[i].substring(2)] = args[i + 1];
  }
  return parsed;
}
