import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log_admin_client/features/resources/presentation/dialogs/team_members_dialog.dart';
import 'package:structured_log_admin_client/shared/api/cursor_page.dart';
import 'package:structured_log_admin_client/shared/api/dto/resource_dto.dart';
import 'package:structured_log_admin_client/shared/api/dto/user_dto.dart';

import '../../support/localized_app.dart';

/// The «Участники» dialog's «Добавить участника» picker (13.2a).
///
/// The picker is remounted when the member list changes, which is how it is
/// cleared after an add. Its key once was the sorted id `List` itself — and a
/// `List` compares by identity, so *every* rebuild remounted it: the first
/// keystroke clears the candidate (`onSelected(null)` → `setState`), the
/// dialog rebuilds, and the field comes back empty and unfocused. Found
/// 02.10.2026 by typing into the release build on the stand.
void main() {
  UserDto user(int id, String username) => UserDto(
    id: id,
    username: username,
    mustChangePassword: false,
    isActive: true,
    isPrimaryAdmin: false,
    createdAt: DateTime.utc(2026, 2, 14),
  );

  final users = [user(9, 'alice'), user(10, 'bob')];

  /// Hosts the dialog the way the page does: the member list comes from
  /// outside and arrives as a fresh `List` on every change, and the host can
  /// rebuild it with an equal-but-new list (what a cubit re-emit looks like).
  Future<_HostState> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final hostKey = GlobalKey<_HostState>();
    await tester.pumpWidget(
      localizedApp(
        home: ScaffoldPage(
          content: Center(
            child: _Host(
              key: hostKey,
              searchUsers: (query) async => CursorPage([
                for (final u in users)
                  if (u.username.contains(query)) u,
              ], null),
              usernameOf: (id) => users.firstWhere((u) => u.id == id).username,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return hostKey.currentState!;
  }

  Finder field() => find.byType(TextBox);

  String fieldText(WidgetTester tester) =>
      tester.widget<TextBox>(field()).controller!.text;

  testWidgets('typed text stays in the field and keeps focus', (tester) async {
    await pump(tester);

    await tester.tap(field());
    await tester.pumpAndSettle();
    await tester.enterText(field(), 'al');
    await tester.pump();

    expect(fieldText(tester), 'al');
    expect(tester.widget<TextBox>(field()).focusNode!.hasFocus, isTrue);

    // The search behind the debounce still runs against what was typed.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('alice'), findsOneWidget);
    expect(find.text('bob'), findsNothing);
  });

  testWidgets('an equal member list arriving again does not clear the field', (
    tester,
  ) async {
    final host = await pump(tester);

    await tester.enterText(field(), 'bo');
    await tester.pump();
    host.reemitMembers();
    await tester.pump();

    expect(fieldText(tester), 'bo');
  });

  testWidgets('the field is cleared once an add changes the member list', (
    tester,
  ) async {
    final host = await pump(tester);

    await tester.tap(field());
    await tester.pumpAndSettle();
    await tester.enterText(field(), 'ali');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('alice'));
    await tester.pumpAndSettle();
    expect(fieldText(tester), 'alice');

    await tester.tap(find.text('Добавить'));
    await tester.pumpAndSettle();

    expect(host.members.map((m) => m.userId), [9]);
    expect(fieldText(tester), isEmpty);
  });
}

class _Host extends StatefulWidget {
  final Future<CursorPage<UserDto>> Function(String query) searchUsers;
  final String Function(int id) usernameOf;

  const _Host({super.key, required this.searchUsers, required this.usernameOf});

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  List<TeamMemberDto> members = const [];

  void reemitMembers() => setState(() => members = [...members]);

  @override
  Widget build(BuildContext context) => TeamMembersDialog(
    teamName: 'on-call',
    groupName: 'payments',
    members: members,
    searchUsers: widget.searchUsers,
    onAdd: (id) => setState(
      () => members = [
        ...members,
        TeamMemberDto(userId: id, username: widget.usernameOf(id)),
      ],
    ),
    onRemove: (id) => setState(
      () => members = [...members]..removeWhere((m) => m.userId == id),
    ),
    onClose: () {},
  );
}
