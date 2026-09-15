import 'package:cherrypick/cherrypick.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:structured_log_admin_ui/structured_log_admin_ui.dart';

/// The application shell.
///
/// `FluentApp`, not `MaterialApp` (design.md decision 38), themed from
/// `structured_log_admin_ui`'s preset so the whole app — including the Fluent
/// widgets this client uses directly — shares one palette.
class AdminApp extends StatelessWidget {
  /// The composition root, handed down so features can open their own
  /// subscopes from it. Widgets resolve from it; none of them construct an
  /// infrastructure dependency.
  final Scope scope;

  const AdminApp({super.key, required this.scope});

  @override
  Widget build(BuildContext context) {
    return FluentApp(
      title: 'Structured Log',
      debugShowCheckedModeBanner: false,
      theme: AdminTheme.light(),
      darkTheme: AdminTheme.dark(),
      home: const _PlaceholderHome(),
    );
  }
}

/// Stands in until section 12 puts the sign-in screen here.
///
/// Deliberately not a blank page: a build that came up with nothing on screen
/// looks identical to one that failed to start.
class _PlaceholderHome extends StatelessWidget {
  const _PlaceholderHome();

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      content: AdminEmptyState(
        icon: FluentIcons.signin,
        title: 'Экран входа ещё не реализован',
        description:
            'Раздел 12 add-structured-log-server. Слой данных, '
            'хранилище токенов и DI уже на месте.',
      ),
    );
  }
}
