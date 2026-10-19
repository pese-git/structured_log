import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_auto_route/structured_log_auto_route.dart';

/// Four screens and two tabs; every push, pop, replacement and tab switch
/// leaves an entry on the console, and the token in the query of the user
/// screen is replaced before it gets there.
///
/// The routes are written by hand so the example needs no code generation;
/// an app that uses `auto_route_generator` passes the observer the same way.
void main() {
  StructlogConfiguration.configure(
    sinks: [LogSink(name: 'console', output: coloredConsoleOutput)],
  );

  runApp(const _App());
}

class _AppRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    AutoRoute(
      page: PageInfo.builder(
        'Home',
        builder: (context, _) => _Screen(
          title: 'Home',
          actions: {
            'Open user 42 (with a token)': () => context.router.push(
              const PageRouteInfo(
                'User',
                rawPathParams: {'id': 42},
                rawQueryParams: {'token': 'secret', 'tab': 'posts'},
              ),
            ),
            'Open the tabs': () =>
                context.router.push(const PageRouteInfo('Shell')),
          },
        ),
      ),
      path: '/',
      initial: true,
    ),
    AutoRoute(
      page: PageInfo.builder(
        'User',
        builder: (context, _) => _Screen(
          title: 'User ${context.routeData.params.getInt('id')}',
          actions: {
            'Replace with settings': () =>
                context.router.replace(const PageRouteInfo('Settings')),
            'Back': () => context.router.maybePop(),
          },
        ),
      ),
      path: '/user/:id',
    ),
    AutoRoute(
      page: PageInfo.builder(
        'Settings',
        builder: (context, _) => _Screen(
          title: 'Settings',
          actions: {'Back': () => context.router.maybePop()},
        ),
      ),
      path: '/settings',
    ),
    AutoRoute(
      page: PageInfo(
        'Shell',
        builder: (_) => AutoTabsRouter(
          routes: const [PageRouteInfo('Feed'), PageRouteInfo('Profile')],
          builder: (context, child) => Scaffold(
            body: child,
            bottomNavigationBar: BottomNavigationBar(
              currentIndex: context.tabsRouter.activeIndex,
              onTap: context.tabsRouter.setActiveIndex,
              items: const [
                BottomNavigationBarItem(icon: Icon(Icons.list), label: 'Feed'),
                BottomNavigationBarItem(
                  icon: Icon(Icons.person),
                  label: 'Profile',
                ),
              ],
            ),
          ),
        ),
      ),
      path: '/shell',
      children: [
        AutoRoute(
          page: PageInfo.builder(
            'Feed',
            builder: (context, _) => const _Screen(title: 'Feed'),
          ),
          path: 'feed',
          initial: true,
        ),
        AutoRoute(
          page: PageInfo.builder(
            'Profile',
            builder: (context, _) => const _Screen(title: 'Profile'),
          ),
          path: 'profile',
        ),
      ],
    ),
  ];
}

class _App extends StatefulWidget {
  const _App();

  @override
  State<_App> createState() => _AppState();
}

class _AppState extends State<_App> {
  final _router = _AppRouter();

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'structured_log_auto_route',
      routerConfig: _router.config(
        navigatorObservers: () => [StructuredLogAutoRouteObserver()],
      ),
    );
  }
}

class _Screen extends StatelessWidget {
  final String title;
  final Map<String, VoidCallback> actions;

  const _Screen({required this.title, this.actions = const {}});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final MapEntry(:key, :value) in actions.entries)
              TextButton(onPressed: value, child: Text(key)),
          ],
        ),
      ),
    );
  }
}
