import 'package:cherrypick/cherrypick.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:structured_log_admin_ui/structured_log_admin_ui.dart';

import '../features/auth/application/restore_session.dart';
import '../features/auth/application/sign_in.dart';
import '../features/auth/di/auth_module.dart';
import '../features/auth/presentation/login_cubit.dart';
import '../features/auth/presentation/login_page.dart';
import '../features/auth/presentation/login_state.dart';
import '../shared/auth/session_controller.dart';
import '../shared/config/app_config.dart';

/// The application shell.
///
/// `FluentApp`, not `MaterialApp` (design.md decision 38), themed from
/// `structured_log_admin_ui`'s preset so the whole app — including the Fluent
/// widgets used directly — shares one palette.
class AdminApp extends StatelessWidget {
  /// The composition root. Features open their own subscopes from it; no
  /// widget constructs an infrastructure dependency.
  final Scope scope;

  /// Whether a session is live, and why it ended if it did.
  final SessionController session;

  const AdminApp({super.key, required this.scope, required this.session});

  @override
  Widget build(BuildContext context) {
    return FluentApp(
      title: 'Structured Log',
      debugShowCheckedModeBanner: false,
      theme: AdminTheme.light(),
      darkTheme: AdminTheme.dark(),
      home: AuthGate(scope: scope, session: session),
    );
  }
}

/// Chooses between the login screen and what is behind it.
///
/// The only place that decides, so neither the login screen nor the
/// interceptor navigates: they report, this listens.
class AuthGate extends StatefulWidget {
  final Scope scope;
  final SessionController session;

  const AuthGate({super.key, required this.scope, required this.session});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final Scope _authScope = openAuthScope(widget.scope);

  /// `null` until the stored session has been looked up — the first frame
  /// must not flash the login screen at someone who is already signed in.
  bool? _restored;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_onSessionChanged);
    _restore();
  }

  Future<void> _restore() async {
    final hasSession = await _authScope.resolve<RestoreSession>()();
    if (!mounted) return;
    if (hasSession) widget.session.signedInNow();
    setState(() => _restored = true);
  }

  void _onSessionChanged() => setState(() {});

  @override
  void dispose() {
    widget.session.removeListener(_onSessionChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_restored == null) {
      return const ScaffoldPage(
        content: Center(child: AdminLoadingIndicator()),
      );
    }

    if (!widget.session.signedIn) {
      return BlocProvider(
        create: (_) => LoginCubit(_authScope.resolve<SignIn>()),
        child: BlocListener<LoginCubit, LoginState>(
          listenWhen: (previous, current) =>
              !previous.signedIn && current.signedIn,
          listener: (_, _) => widget.session.signedInNow(),
          child: LoginPage(
            serverLabel: _serverLabel,
            sessionExpired: widget.session.expired,
          ),
        ),
      );
    }

    return const _PlaceholderHome();
  }

  /// Host and port of the deployment this window talks to, or `null` when
  /// there is nothing worth showing.
  ///
  /// The base URL is empty in the bundled deployment — the client is served
  /// beside the API and addresses it relative to the page — so the page's own
  /// origin is the honest answer there. Printing "Сервер:" with nothing after
  /// it, which is what an empty base URL produced before, told the operator
  /// less than saying nothing.
  String? get _serverLabel {
    final configured = widget.scope.resolve<AppConfig>().baseUrl;
    final authority = configured.isEmpty
        ? Uri.base.authority
        : (Uri.tryParse(configured)?.authority ?? configured);
    return authority.isEmpty ? null : authority;
  }
}

/// Stands in until section 13/14 put real screens behind sign-in.
///
/// Deliberately not blank: a build that came up with nothing on screen looks
/// identical to one that failed to start.
class _PlaceholderHome extends StatelessWidget {
  const _PlaceholderHome();

  @override
  Widget build(BuildContext context) {
    return const ScaffoldPage(
      content: AdminEmptyState(
        icon: FluentIcons.completed,
        title: 'Вход выполнен',
        description:
            'Экраны проектов и логов — разделы 13 и 14 '
            'add-structured-log-server.',
      ),
    );
  }
}
