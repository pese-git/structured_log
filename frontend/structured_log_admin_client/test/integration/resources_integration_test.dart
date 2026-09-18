import 'package:cherrypick/cherrypick.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_harness.dart';
import 'package:structured_log_admin_client/testing/mock_server.dart';

/// Groups, projects and secret keys, driven through the screens and answered
/// over the wire.
///
/// The screen tests cover the same gestures against a fake repository, which
/// is deliberately a different question: those ask whether the widget does the
/// right thing with an answer, these ask whether the answer survives the
/// journey. The collection envelope is the standing example — the list
/// methods were once declared as `Future<List<GroupDto>>`, dio's cast threw on
/// the server's `{"items": [...]}`, and the screen reported it as "the server
/// is unreachable" while the server answered 200. No fake repository could
/// have shown that; a mock that speaks the server's actual body does.
void main() {
  late MockServer server;

  setUp(() {
    server = MockServer();
    server.groups.add({
      'id': 7,
      'name': 'acme',
      'created_at': '2026-02-14T00:00:00.000Z',
    });
    server.projects.add({
      'id': 1,
      'group_id': 7,
      'name': 'payments',
      'retention_days': 30,
      'max_entries': 1000,
      'max_bytes': null,
      'is_blocked': false,
      'created_at': '2026-02-14T00:00:00.000Z',
      'entry_count': 842,
      'total_bytes': 5 * 1024 * 1024,
    });
  });

  tearDown(CherryPick.closeRootScope);

  RecordedRequest lastRequest(String method, String path) => server.requests
      .lastWhere((request) => request.method == method && request.path == path);

  /// Groups → one group → one project, the way the breadcrumb reads.
  Future<void> openProject(WidgetTester tester) async {
    await tester.tap(find.text('Открыть').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Открыть').first);
    await tester.pumpAndSettle();
  }

  testWidgets('the group list is read out of the server\'s own envelope', (
    tester,
  ) async {
    await pumpApp(tester, server, signedIn: true);

    expect(
      find.text('acme'),
      findsOneWidget,
      reason:
          'the body is {"items": [...]}, never a bare array — a client that '
          'expects the array reports a working server as unreachable',
    );
    expect(find.text('Групп пока нет'), findsNothing);
    await closeApp(tester);
  });

  testWidgets('a group typed into the dialog is created and comes back in the '
      'list', (tester) async {
    await pumpApp(tester, server, signedIn: true);

    await tester.tap(find.text('Создать группу'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextBox).first, 'billing');
    await tester.tap(find.text('Создать группу').last);
    await tester.pumpAndSettle();

    expect(lastRequest('POST', '/v1/groups').json, {'name': 'billing'});
    expect(
      find.text('billing'),
      findsOneWidget,
      reason: 'the dialog closes itself and the reloaded list shows it',
    );
    await closeApp(tester);
  });

  testWidgets('a refusal from the server is explained inside the dialog', (
    tester,
  ) async {
    server.script(
      'POST',
      '/v1/groups',
      const MockReply(
        403,
        body: {'error': 'forbidden', 'message': 'Admins only.'},
      ),
    );
    await pumpApp(tester, server, signedIn: true);

    await tester.tap(find.text('Создать группу'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextBox).first, 'billing');
    await tester.tap(find.text('Создать группу').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('Недостаточно прав'), findsOneWidget);
    expect(
      find.text('Название группы'),
      findsOneWidget,
      reason:
          'the dialog stays open so the reason is read where the attempt '
          'was made',
    );
    await closeApp(tester);
  });

  testWidgets('usage counters come only from the project\'s own endpoint', (
    tester,
  ) async {
    await pumpApp(tester, server, signedIn: true);
    await openProject(tester);

    expect(
      lastRequest('GET', '/v1/projects/1').path,
      '/v1/projects/1',
      reason: 'the list carries no counters; this is the only place they exist',
    );
    // "842 / 1 000" — the scenario in the spec, with a non-breaking space
    // inside the number.
    expect(find.textContaining('842'), findsOneWidget);
    expect(find.textContaining('1\u00A0000'), findsOneWidget);
    expect(find.text('30 дней'), findsOneWidget);
    await closeApp(tester);
  });

  testWidgets('an unset limit is left off the create request entirely', (
    tester,
  ) async {
    await pumpApp(tester, server, signedIn: true);
    await tester.tap(find.text('Открыть').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Проект'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextBox).first, 'billing-api');
    await tester.tap(find.text('Создать проект'));
    await tester.pumpAndSettle();

    final body = lastRequest('POST', '/v1/groups/7/projects').json;
    expect(body['name'], 'billing-api');
    expect(body['retention_days'], 30);
    expect(
      body.containsKey('max_entries'),
      isFalse,
      reason:
          'on create, an absent key means "unset" — the create DTO omits '
          'nulls, and only the update DTO sends them',
    );
    expect(find.text('billing-api'), findsOneWidget);
    await closeApp(tester);
  });

  testWidgets('clearing a limit sends an explicit null, and the counters '
      'already shown survive the answer', (tester) async {
    await pumpApp(tester, server, signedIn: true);
    await openProject(tester);

    await tester.tap(find.text('Изменить квоту'));
    await tester.pumpAndSettle();
    // The first of the two "без лимита" boxes is the entry limit's.
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();

    final body = lastRequest('PATCH', '/v1/projects/1').json;
    expect(
      body.containsKey('max_entries'),
      isTrue,
      reason:
          'the server tells "leave this alone" from "make this unlimited" by '
          'whether the key is on the wire — omitting it would mean unchanged',
    );
    expect(body['max_entries'], isNull);
    expect(server.projects.single['max_entries'], isNull);
    expect(
      find.textContaining('842'),
      findsOneWidget,
      reason:
          'the PATCH answer carries no entry_count, and the screen keeps the '
          'one it already had rather than showing zero',
    );
    await closeApp(tester);
  });

  testWidgets('a created key is revealed once, and never travels again', (
    tester,
  ) async {
    await pumpApp(tester, server, signedIn: true);
    await openProject(tester);
    expect(find.text('Секретных ключей пока нет'), findsOneWidget);

    await tester.tap(find.text('Создать ключ'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextBox).first, 'ci');
    await tester.tap(find.text('Создать ключ').last);
    await tester.pumpAndSettle();

    expect(find.text('Ключ создан'), findsOneWidget);
    expect(find.text('slk_live_1'), findsOneWidget);
    expect(find.textContaining('только один раз'), findsOneWidget);

    await tester.tap(find.text('Я сохранил(а) ключ — закрыть'));
    await tester.pumpAndSettle();

    expect(
      find.text('slk_live_1'),
      findsNothing,
      reason: 'nothing in the app holds the value once the dialog is gone',
    );
    expect(find.text('ci'), findsOneWidget);
    expect(find.text('Активен'), findsOneWidget);
    await closeApp(tester);
  });

  testWidgets('a revoked key stays listed, with the date the server gave it', (
    tester,
  ) async {
    server.secretKeys.add({
      'id': 4,
      'project_id': 1,
      'label': 'legacy',
      'created_at': '2025-11-20T00:00:00.000Z',
      'revoked_at': null,
    });
    await pumpApp(tester, server, signedIn: true);
    await openProject(tester);

    await tester.tap(find.text('Отозвать'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отозвать').last);
    await tester.pumpAndSettle();

    expect(lastRequest('DELETE', '/v1/projects/1/secret-keys/4'), isNotNull);
    expect(server.secretKeys.single['revoked_at'], isNotNull);
    expect(find.text('legacy'), findsOneWidget);
    expect(find.textContaining('Отозван'), findsOneWidget);
    expect(
      find.text('Отозвать'),
      findsNothing,
      reason: 'there is nothing left to revoke',
    );
    await closeApp(tester);
  });

  testWidgets('a blocked project looks blocked wherever it is shown', (
    tester,
  ) async {
    server.projects.single['is_blocked'] = true;
    await pumpApp(tester, server, signedIn: true);
    await openProject(tester);

    expect(find.text('Заблокирован'), findsWidgets);
    expect(find.textContaining('заблокирован администратором'), findsOneWidget);
    await closeApp(tester);
  });

  group('access', () {
    setUp(() {
      server.users.add({
        'id': 9,
        'username': 'alice',
        'display_name': null,
        'email': null,
        'email_verified_at': null,
        'must_change_password': false,
        'is_active': true,
        'deleted_at': null,
        'is_primary_admin': false,
        'created_at': '2026-02-14T00:00:00.000Z',
      });
    });

    testWidgets('granting on a project searches users by name, not id', (
      tester,
    ) async {
      await pumpApp(tester, server, signedIn: true);
      await openProject(tester);
      expect(find.text('Доступа пока никому не выдано'), findsOneWidget);

      await tester.tap(find.text('Предоставить доступ'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextBox).last, 'ali');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await tester.tap(find.text('alice').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Предоставить').last);
      await tester.pumpAndSettle();

      final sent = lastRequest('POST', '/v1/role-assignments').json;
      expect(sent, {
        'subject_type': 'user',
        'subject_id': 9,
        'role': 'user',
        'scope_type': 'project',
        'scope_id': 1,
      });
      expect(
        find.text('alice'),
        findsOneWidget,
        reason: 'the dialog closes itself and the reloaded list shows it',
      );
      await closeApp(tester);
    });

    testWidgets(
      'granting a team searches the project\'s own group by name, not id '
      '(13.5, full version)',
      (tester) async {
        server.teams.add({
          'id': 3,
          'group_id': 7,
          'name': 'on-call',
          'created_at': '2026-02-14T00:00:00.000Z',
        });
        await pumpApp(tester, server, signedIn: true);
        await openProject(tester);

        await tester.tap(find.text('Предоставить доступ'));
        await tester.pumpAndSettle();
        // The recipient-kind picker is the first ComboBox<String> in the
        // dialog — the role picker is the second.
        await tester.tap(find.byType(ComboBox<String>).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Команда').last);
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextBox).last, 'on');
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        await tester.tap(find.text('on-call').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Предоставить').last);
        await tester.pumpAndSettle();

        final sent = lastRequest('POST', '/v1/role-assignments').json;
        expect(sent, {
          'subject_type': 'team',
          'subject_id': 3,
          'role': 'user',
          'scope_type': 'project',
          'scope_id': 1,
        });
        expect(
          find.text('on-call'),
          findsOneWidget,
          reason: 'the dialog closes itself and the reloaded list shows it',
        );
        await closeApp(tester);
      },
    );

    testWidgets('revoking removes the row', (tester) async {
      server.roleAssignments.add({
        'id': 1,
        'subject_type': 'user',
        'subject_id': 9,
        'role': 'owner',
        'scope_type': 'project',
        'scope_id': 1,
        'created_at': '2026-02-14T00:00:00.000Z',
      });
      await pumpApp(tester, server, signedIn: true);
      await openProject(tester);
      expect(find.text('alice'), findsOneWidget);

      await tester.tap(find.text('Отозвать'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Отозвать').last);
      await tester.pumpAndSettle();

      expect(lastRequest('DELETE', '/v1/role-assignments/1'), isNotNull);
      expect(find.text('alice'), findsNothing);
      expect(find.text('Доступа пока никому не выдано'), findsOneWidget);
      await closeApp(tester);
    });
  });
}
