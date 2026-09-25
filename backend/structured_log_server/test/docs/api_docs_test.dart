import 'dart:io';

import 'package:structured_log_server/src/storage/log_filter.dart';
import 'package:test/test.dart';

/// Keeps the API documentation from drifting away from what the server
/// actually answers.
///
/// The sibling of `config/configuration_docs_test.dart`, guarding the other
/// half of what a reader copies out of the docs. That one watches flag
/// spellings, because a wrong one costs a failed deployment; this one
/// watches the two claims the API docs make that the code can check.
///
/// Not hypothetical, and the shape of the failure is worth recording. On
/// 25.09.2026 the docs listed the levels without `trace` in six places and
/// quoted, in four more, a rejection message the server has never emitted —
/// `"level: must be one of debug, info, warning, error, critical"` against
/// the server's own `trace, debug, …`. One of those six sat forty lines
/// below a sentence in the same file saying "Six levels, least to most
/// severe: `trace` < `debug` < …", so the document contradicted itself and
/// no test minded. It was found by a reader trying the endpoint, which is
/// the only way it could have been found: nothing in the code reads the
/// docs, so nothing in the suite had an opinion about them.
///
/// Two rules, both fail-closed:
///
/// - **Every enumeration of levels is the whole set, in order.** Runs of
///   three or more level names joined by `/`, `,` or `<` are found and
///   compared against [logLevelOrder]. Three is the threshold because a
///   shorter run is prose naming a couple of levels ("`error` and
///   `critical` are…"), not a claim about what the set *is*.
/// - **Every quoted rejection message is the one the server builds.**
///   `ingest.dart` composes it from [logLevelOrder], so a doc that spells
///   the list differently is quoting something that never happened.
///
/// The scan runs over the joined text of each file rather than line by
/// line, because these lists wrap: `trace`/`debug`/ on one line and
/// `info`/`warning`/… on the next is one enumeration, and a line-wise
/// reading would call it two incomplete ones.
///
/// Scope is [_documents] — the system documentation under `docs/` and the
/// server's own READMEs. The `emb/` package READMEs are left out on
/// purpose: their levels come from `structured_log`'s `LogLevel`, which
/// this package does not own, and a guard that reached into another
/// package's documentation would be asserting against the wrong source.

/// Package-relative paths. `dart test` runs with the package directory as
/// the working directory, which is also how `melos run test` invokes it.
const _documents = [
  'README.md',
  'README.ru.md',
  '../../docs/api',
  '../../docs/guides',
  '../../docs/architecture',
];

/// A level name, with or without the backticks the docs put around it.
final _levelName = RegExp('`?(?:${logLevelOrder.join('|')})`?');

/// Three or more level names in a row, joined the way the docs join them:
/// `/` in a table cell, `,` in a quoted message, `<` in the sentence that
/// orders them by severity.
final _levelRun = RegExp(
  '${_levelName.pattern}(?:\\s*[/,<]\\s*${_levelName.pattern}){2,}',
);

/// The message `ingest.dart` gives an entry whose `level` it does not know,
/// built here the same way so that changing one side reddens this test
/// rather than silently parting from the other.
final _rejection = 'level: must be one of ${logLevelOrder.join(', ')}';

/// Anything in a document that starts like [_rejection] but may not finish
/// like it.
final _rejectionClaim = RegExp('level: must be one of [a-z, ]+');

Iterable<File> _markdownUnder(String path) {
  final directory = Directory(path);
  if (directory.existsSync()) {
    return directory
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.md'));
  }
  return [File(path)];
}

/// Every document in scope, as (path, whitespace-collapsed contents).
List<(String, String)> _scanned() => [
  for (final entry in _documents)
    for (final file in _markdownUnder(entry))
      (file.path, file.readAsStringSync().replaceAll(RegExp(r'\s+'), ' ')),
];

void main() {
  group('the API docs agree with the server', () {
    late List<(String, String)> documents;

    setUp(() => documents = _scanned());

    test('the scan reaches real documents', () {
      // Without this the rules below pass by finding nothing at all — a
      // moved directory or a renamed file would turn the whole test green
      // and silent, which is the failure it exists to prevent.
      expect(documents, isNotEmpty, reason: 'no documents in scope');
      expect(
        documents.where((d) => _levelRun.hasMatch(d.$2)),
        isNotEmpty,
        reason: 'no level enumeration found anywhere — the pattern is stale',
      );
    });

    test('every enumeration of levels is the whole set, in order', () {
      final wrong = <String>[];
      for (final (path, text) in documents) {
        for (final match in _levelRun.allMatches(text)) {
          final run = match.group(0)!;
          final named = RegExp(
            logLevelOrder.join('|'),
          ).allMatches(run).map((m) => m.group(0)).toList();
          if (named.toString() != logLevelOrder.toString()) {
            wrong.add('$path: $named\n    in: $run');
          }
        }
      }

      expect(
        wrong,
        isEmpty,
        reason:
            'these enumerations are not ${logLevelOrder.join('/')}:\n'
            '  ${wrong.join('\n  ')}',
      );
    });

    test('every quoted rejection message is the one the server builds', () {
      final wrong = <String>[];
      for (final (path, text) in documents) {
        for (final match in _rejectionClaim.allMatches(text)) {
          final quoted = match.group(0)!.trimRight();
          if (quoted != _rejection) wrong.add('$path: "$quoted"');
        }
      }

      expect(
        wrong,
        isEmpty,
        reason:
            'the server says "$_rejection"; these quote something else:\n'
            '  ${wrong.join('\n  ')}',
      );
    });
  });
}
