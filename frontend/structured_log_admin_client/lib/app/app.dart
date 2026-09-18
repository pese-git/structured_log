import 'package:cherrypick/cherrypick.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:structured_log_admin_ui/structured_log_admin_ui.dart';

import '../features/auth/application/change_password.dart';
import '../features/auth/application/restore_session.dart';
import '../features/auth/application/sign_in.dart';
import '../features/auth/application/sign_out.dart';
import '../features/auth/di/auth_module.dart';
import '../features/auth/presentation/change_password_cubit.dart';
import '../features/auth/presentation/force_password_change_page.dart';
import '../features/auth/presentation/login_cubit.dart';
import '../features/auth/presentation/login_page.dart';
import '../features/auth/presentation/login_state.dart';
import '../l10n/l10n.dart';
import '../shared/auth/session_controller.dart';
import '../shared/l10n/locale_controller.dart';
import 'home_shell.dart';
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

  /// The chosen language. Absent, the app follows the browser's — English
  /// when that is a language the client has no translation of.
  final LocaleController? localeController;

  const AdminApp({
    super.key,
    required this.scope,
    required this.session,
    this.localeController,
  });

  @override
  Widget build(BuildContext context) {
    final controller = localeController;
    if (controller == null) return _app(null);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => _app(controller.locale),
    );
  }

  Widget _app(Locale? locale) {
    return FluentApp(
      onGenerateTitle: (context) => context.l10n.appTitle,
      debugShowCheckedModeBanner: false,
      theme: AdminTheme.light(),
      darkTheme: AdminTheme.dark(),
      locale: locale,
      localizationsDelegates: adminLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: AuthGate(
        scope: scope,
        session: session,
        localeController: localeController,
      ),
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
  final LocaleController? localeController;

  const AuthGate({
    super.key,
    required this.scope,
    required this.session,
    this.localeController,
  });

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

    // The gate outranks everything behind it: while it holds, the server
    // answers 403 to every other endpoint, so there is no screen to show
    // (`specs/admin-client-auth`).
    if (widget.session.mustChangePassword) {
      return BlocProvider(
        create: (_) => ChangePasswordCubit(
          changePassword: _authScope.resolve<ChangePassword>(),
          currentUsername: _authScope.resolve<CurrentUsername>(),
        ),
        child: ForcePasswordChangePage(
          onChanged: widget.session.passwordChanged,
          onSignOut: _signOut,
        ),
      );
    }

    return HomeShell(
      scope: widget.scope,
      session: widget.session,
      localeController: widget.localeController,
    );
  }

  Future<void> _signOut() async {
    await _authScope.resolve<SignOut>()();
    widget.session.signedOutNow();
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
