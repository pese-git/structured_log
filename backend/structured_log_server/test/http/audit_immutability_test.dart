import 'dart:io';

import 'package:test/test.dart';

/// The audit log has no delete path, and this is what keeps it that way.
///
/// An audit log an administrator can edit answers a different question from
/// one they cannot: the first says only what someone was willing to leave on
/// the record. So there is no endpoint that mutates it, and the only deletion
/// is the retention purge — automatic, bounded by configuration, and recorded
/// in the log itself (`specs/log-server-audit`).
///
/// Absence needs no implementation, which is exactly why it needs a test.
/// Nothing else in the suite would notice a `DELETE /v1/audit-log/<id>` added
/// in good faith — to clear test data, or to let an operator drop a record they
/// consider noise.
void main() {
  test('no route mutates the audit log', () {
    final offenders = <String>[];

    for (final route in declaredRoutes()) {
      if (!route.path.contains('audit')) continue;
      if (route.verb == 'GET') continue;
      offenders.add('${route.verb} ${route.path} (${route.file})');
    }

    expect(
      offenders,
      isEmpty,
      reason: 'the audit log is readable and nothing else; a write path to it '
          'turns every record in it from a fact into a claim',
    );
  });

  test('no source deletes audit rows', () {
    // The route check above only sees what is reachable over HTTP. This one
    // sees a helper, a cleanup routine or a CLI command reaching the table
    // directly — the purge job excepted, which is the one sanctioned deletion
    // and lives somewhere this deliberately does not look.
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.endsWith('.g.dart')) continue;
      if (entity.path.contains('/retention/')) continue;

      final deletesAudit = RegExp(
        r'delete\(\s*\w*\.?auditLogEntries|DELETE\s+FROM\s+audit_log_entries',
        caseSensitive: false,
      );
      for (final line in entity.readAsStringSync().split('\n')) {
        // Comments discuss the rule; only code can break it.
        if (deletesAudit.hasMatch(line.split('//').first)) {
          offenders.add('${entity.path}: ${line.trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'only the retention purge may delete audit rows, and it accounts for '
          'itself in the audit log when it does',
    );
  });

  test('the scan reads both spellings of the annotation', () {
    // The check above passes trivially if its pattern misses what it looks
    // for — and the first draft did exactly that, matching only
    // `@Route('PATCH', ...)` while ignoring every `@Route.delete(...)`, which
    // is the spelling an offence would actually be written in. Caught by
    // adding the offence and watching the test stay green. So the scan is now
    // asserted against routes known to exist, one of each spelling.
    final routes = declaredRoutes();
    expect(routes.length, greaterThan(10));

    expect(
      routes.any((r) => r.verb == 'GET' && r.path == '/v1/audit-log'),
      isTrue,
      reason: 'named constructor: @Route.get',
    );
    expect(
      routes.any((r) => r.verb == 'DELETE' && r.path.contains('secret-keys')),
      isTrue,
      reason: 'the spelling an offence would use: @Route.delete',
    );
    expect(
      routes.any((r) => r.verb == 'PATCH' && r.path.contains('projects')),
      isTrue,
      reason: "the generic spelling: @Route('PATCH', ...)",
    );
  });
}

/// Every route the source declares, read as text.
///
/// Both spellings `shelf_router` accepts, because only one of them is what
/// someone deleting audit records would reach for: `@Route.delete('/path')`
/// and `@Route('DELETE', '/path')`.
List<({String verb, String path, String file})> declaredRoutes() {
  final named = RegExp(r"@Route\.(\w+)\(\s*'([^']+)'");
  final generic = RegExp(r"@Route\(\s*'(\w+)'\s*,\s*'([^']+)'");

  final routes = <({String verb, String path, String file})>[];
  for (final file in Directory('lib/src/http/routes')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('_route.dart'))) {
    final source = file.readAsStringSync();
    for (final pattern in [named, generic]) {
      for (final match in pattern.allMatches(source)) {
        routes.add((
          verb: match.group(1)!.toUpperCase(),
          path: match.group(2)!,
          file: file.path,
        ));
      }
    }
  }
  return routes;
}
