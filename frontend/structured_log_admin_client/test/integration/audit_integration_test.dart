import 'package:cherrypick/cherrypick.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log_admin_client/shared/api/dto/audit_dto.dart';
import 'package:structured_log_admin_client/testing/mock_server.dart';

import 'app_harness.dart';

/// The audit screen against the mock network layer — the whole client stack
/// underneath it: real `dio`, the auth interceptor, the generated client, the
/// DTOs, the cubit and the widgets.
///
/// What these cover that `test/features/audit/` cannot: that the section is
/// wired into the shell at all, that the role claim actually reaches the nav,
/// and that a refusal travels from bytes to a sentence on screen.
void main() {
  /// A reader with no global admin role. There is no endpoint in this stage
  /// that creates a second account, so the only way to be someone else is to
  /// say what the token claims.
  MockServer nonAdminServer() => MockServer(
    roles: const [
      {'role': 'owner', 'scope_type': 'group', 'scope_id': 1},
    ],
  );

  void seed(MockServer server) {
    server
      ..auditRetentionDays = 365
      ..authEventRetentionDays = 90;
    server.auditEntries.addAll([
      mockAuditEntry(
        id: 1,
        action: 'group.created',
        targetType: 'group',
        actorUserId: 1,
        targetId: 4,
        metadata: const {'name': 'Acme Corp'},
        createdAt: DateTime.utc(2026, 9, 12, 6),
      ),
      mockAuditEntry(
        id: 2,
        action: 'auth.login_failed',
        targetType: 'user',
        metadata: const {
          'reason': 'unknown_user',
          'unknown_user': true,
          'client_ip': '198.51.100.44',
        },
        createdAt: DateTime.utc(2026, 9, 13, 6),
      ),
    ]);
  }

  tearDown(CherryPick.closeRootScope);

  testWidgets('an administrator reaches the journal from the nav', (
    tester,
  ) async {
    final server = MockServer();
    seed(server);

    await pumpApp(tester, server, signedIn: true);
    await openAudit(tester);

    expect(find.text('group.created'), findsOneWidget);
    expect(find.text('auth.login_failed'), findsOneWidget);
    expect(
      find.text('Административные действия: 365 дней'),
      findsOneWidget,
      reason: 'the retention the page reported, not a client-side default',
    );

    // The request the screen actually made, seen from the network side.
    final audit = server.requests
        .where((r) => r.path == '/v1/audit-log')
        .toList();
    expect(audit, hasLength(1));
    expect(
      audit.single.query,
      {'limit': '50'},
      reason:
          'no filter, and the page size asked for rather than left to the server',
    );

    await closeApp(tester);
  });

  testWidgets('a record with nobody behind it is named, not looked up', (
    tester,
  ) async {
    final server = MockServer();
    seed(server);

    await pumpApp(tester, server, signedIn: true);
    await openAudit(tester);

    expect(find.text('учётной записи не существует'), findsOneWidget);
    expect(
      find.textContaining('unknown_user: да'),
      findsOneWidget,
      reason: 'the metadata is rendered as pairs, not as raw JSON',
    );
    expect(
      server.requests.where((r) => r.path.startsWith('/v1/users')),
      isEmpty,
      reason:
          'there is no account to resolve, so nothing may go looking for one',
    );

    await closeApp(tester);
  });

  testWidgets('a filter reaches the server and resets the page', (
    tester,
  ) async {
    final server = MockServer();
    seed(server);

    await pumpApp(tester, server, signedIn: true);
    await openAudit(tester);

    // The ComboBox itself, not its placeholder text: the text sits inside the
    // control's own padding and a tap on it lands on the box around it.
    await tester.tap(find.byType(ComboBox<AuditAction?>));
    await tester.pumpAndSettle();

    // Chosen from the top of the menu on purpose. The list is virtualised, so
    // an action twenty rows down is not built until the menu is scrolled —
    // which is a fact about the test, not about the screen.
    await tester.tap(find.text('Группа создана · group.created').last);
    await tester.pumpAndSettle();

    final audit = server.requests
        .where((r) => r.path == '/v1/audit-log')
        .toList();
    expect(audit, hasLength(2));
    expect(audit.last.query, {'action': 'group.created', 'limit': '50'});
    expect(
      audit.last.query.containsKey('cursor'),
      isFalse,
      reason: 'a changed filter starts over rather than paging the old query',
    );
    expect(
      find.text('auth.login_failed'),
      findsNothing,
      reason: 'the narrowed page replaced the old one rather than adding to it',
    );

    await closeApp(tester);
  });

  testWidgets('a reader without the role is not offered the section', (
    tester,
  ) async {
    final server = nonAdminServer();
    seed(server);

    await pumpApp(tester, server, signedIn: true);

    expect(find.text('Аудит'), findsNothing);
    expect(
      find.text('Группы'),
      findsWidgets,
      reason: 'the rest of the nav is unaffected — only one item is withheld',
    );
    expect(
      server.requests.where((r) => r.path == '/v1/audit-log'),
      isEmpty,
      reason: 'a section that is not offered is not fetched either',
    );

    await closeApp(tester);
  });

  testWidgets('a refusal is rendered as a refusal, not as a crash', (
    tester,
  ) async {
    // The nav item is decided by an unverified claim, so a token that claims
    // admin while the server disagrees is exactly the case the screen has to
    // survive — and the artificial version here is the honest stand-in for a
    // role revoked mid-session.
    final server = MockServer();
    seed(server);
    server.standingAnswer = (request) => request.path == '/v1/audit-log'
        ? const MockReply(403, body: {'error': 'forbidden'})
        : null;

    await pumpApp(tester, server, signedIn: true);
    await openAudit(tester);

    expect(find.text('Журнал не загружен'), findsOneWidget);
    expect(find.textContaining('доступен только администратору'), findsWidgets);

    await closeApp(tester);
  });
}
