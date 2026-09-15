import 'package:cherrypick/cherrypick.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:structured_log_admin_ui/structured_log_admin_ui.dart';

import '../features/auth/application/sign_out.dart';
import '../features/log_browser/di/log_browser_module.dart';
import '../features/log_browser/presentation/log_browser_cubit.dart';
import '../features/log_browser/presentation/log_browser_page.dart';
import '../shared/auth/session_controller.dart';

/// What the application is once someone is signed in.
///
/// One section so far — the log browser. Users, groups and projects are
/// sections 13's, and the shell's navigation is where they will appear;
/// nothing here is per-feature except the list of entries.
class HomeShell extends StatefulWidget {
  final Scope scope;
  final SessionController session;

  const HomeShell({super.key, required this.scope, required this.session});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late final Scope _logScope = openLogBrowserScope(widget.scope);
  var _navIndex = 0;

  Future<void> _signOut() async {
    // The local session ends whatever the server answers, including when it
    // cannot be reached (`specs/admin-client-auth`), so there is nothing to
    // check here.
    await widget.scope.openSubScope('auth').resolve<SignOut>()();
    widget.session.signedOutNow();
  }

  @override
  Widget build(BuildContext context) {
    return AdminAppShell(
      title: 'Поиск логов',
      accountName: 'Администратор',
      accountRole: 'Выйти',
      onAccountPressed: _signOut,
      selectedIndex: _navIndex,
      onSelected: (index) => setState(() => _navIndex = index),
      sections: const [
        AdminNavSection(
          title: 'Логи',
          items: [AdminNavItem(icon: FluentIcons.search, label: 'Поиск логов')],
        ),
      ],
      content: BlocProvider(
        create: (_) => _logScope.resolve<LogBrowserCubit>(),
        child: const LogBrowserPage(),
      ),
    );
  }
}
