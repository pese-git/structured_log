import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_go_router/structured_log_go_router.dart';

/// Three screens and a redirect; every navigation, the redirect and the
/// not-found page each leave an entry on the console.
void main() {
  StructlogConfiguration.configure(
    sinks: [LogSink(name: 'console', output: coloredConsoleOutput)],
  );

  final routeLog = StructuredLogGoRouter();
  var signedIn = false;

  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        name: 'home',
        builder: (context, state) => _Screen(
          title: 'Home',
          actions: {
            'Open user 42': () => context.go('/users/42'),
            'Open settings (needs sign-in)': () => context.go('/settings'),
            'Open a missing page': () => context.go('/nowhere'),
          },
        ),
        routes: [
          GoRoute(
            path: 'users/:id',
            name: 'user',
            builder: (context, state) => _Screen(
              title: 'User ${state.pathParameters['id']}',
              actions: {'Back home': () => context.go('/')},
            ),
          ),
          GoRoute(
            path: 'settings',
            builder: (context, state) => _Screen(
              title: 'Settings',
              actions: {'Back home': () => context.go('/')},
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => _Screen(
          title: 'Sign in',
          actions: {
            'Sign in': () {
              signedIn = true;
              context.go('/settings');
            },
          },
        ),
      ),
    ],
    // Wrapped, so each redirect it makes is logged as route_redirected.
    redirect: routeLog.redirect(
      (context, state) =>
          !signedIn && state.uri.path == '/settings' ? '/login' : null,
    ),
    errorBuilder: (context, state) => _Screen(
      title: 'Not found',
      actions: {'Back home': () => context.go('/')},
    ),
  );
  routeLog.attach(router);

  runApp(MaterialApp.router(routerConfig: router));
}

class _Screen extends StatelessWidget {
  final String title;
  final Map<String, VoidCallback> actions;

  const _Screen({required this.title, required this.actions});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: ListView(
      children: [
        for (final MapEntry(:key, :value) in actions.entries)
          ListTile(title: Text(key), onTap: value),
      ],
    ),
  );
}
