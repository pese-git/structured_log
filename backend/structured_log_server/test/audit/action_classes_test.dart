import 'dart:io';

import 'package:structured_log_server/src/audit/action_classes.dart';
import 'package:structured_log_server/src/audit/audit_action.dart';
import 'package:test/test.dart';

/// The closed set, checked against the thing that made it closed.
void main() {
  test('every action falls in exactly one retention class', () {
    for (final action in AuditAction.values) {
      expect(
        isAuthEvent(action) != isAdminAction(action),
        isTrue,
        reason: '${action.wire} is in both classes or in neither — the two '
            'retention periods would then either both delete it or neither '
            'would (`design.md` decision 46)',
      );
    }
  });

  test('the four authentication events are the authentication class', () {
    expect(
      AuditAction.values.where(isAuthEvent).map((a) => a.wire).toSet(),
      {
        'auth.login_succeeded',
        'auth.login_failed',
        'auth.logged_out',
        'auth.throttled',
      },
      reason:
          'these carry client_ip/user_agent and are produced by traffic nobody '
          'here controls, which is why they have their own period',
    );
  });

  test('the purge record is administrative but keeps no transaction', () {
    // It is an administrative fact — an operator needs it long after the rows
    // it describes are gone — but there is no mutation for it to be atomic
    // with, and `specs/log-server-audit` exempts it by name alongside `auth.*`.
    expect(isAdminAction(AuditAction.auditPurged), isTrue);
    expect(requiresEnclosingTransaction(AuditAction.auditPurged), isFalse);

    expect(requiresEnclosingTransaction(AuditAction.groupCreated), isTrue);
    expect(requiresEnclosingTransaction(AuditAction.authLoginFailed), isFalse);
  });

  test('the wire strings are the ones the specification names', () {
    // The spec's requirement 1 is the contract, and it is a prose sentence —
    // nothing else in the build compares the two. A typo like
    // `secretkey.revoked` would compile, store, and be undiscoverable by any
    // reader filtering for the name the spec promised.
    final spec = File(
      '../../openspec/changes/add-structured-log-server/specs/'
      'log-server-audit/spec.md',
    );
    expect(
      spec.existsSync(),
      isTrue,
      reason: 'the capability spec is the source this set answers to',
    );

    final requirement = spec
        .readAsStringSync()
        .split('### Requirement:')
        .firstWhere((section) => section.contains('закрытый список'));
    final named = RegExp(r'`([a-z_]+\.[a-z_]+)`')
        .allMatches(requirement.split('#### Scenario:').first)
        .map((m) => m.group(1)!)
        .toSet();

    expect(
      AuditAction.values.map((a) => a.wire).toSet(),
      named,
      reason: 'the enum and the specification must name the same twenty-five '
          'actions — a value in one and not the other is a hole in a set whose '
          'only purpose is being closed',
    );
  });

  test('a stored row names its action, and an unknown one is not fatal', () {
    expect(AuditAction.fromWire('group.created'), AuditAction.groupCreated);
    expect(
      AuditAction.fromWire('group.renamed'),
      isNull,
      reason:
          'a row written by another build should cost a reader that row, not '
          'the whole page',
    );
  });
}
