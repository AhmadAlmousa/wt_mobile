import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/session_manager.dart';
import '../features/access/access_screen.dart';
import '../features/auth/sign_in_screen.dart';
import '../features/connect/connect_screen.dart';
import 'theme.dart';

/// The application shell.
class WebtreesMobileApp extends StatefulWidget {
  const WebtreesMobileApp({required this.session, super.key});

  final SessionManager session;

  @override
  State<WebtreesMobileApp> createState() => _WebtreesMobileAppState();
}

class _WebtreesMobileAppState extends State<WebtreesMobileApp> {
  late final GoRouter _router = GoRouter(
    initialLocation: Routes.connect,
    // Rebuilds the routing decision whenever the session changes, so an
    // expired session cannot leave a signed-out user on a signed-in screen.
    refreshListenable: widget.session,
    redirect: (context, state) {
      final signedIn = widget.session.isSignedIn;
      final connected = widget.session.instance != null;
      final location = state.matchedLocation;

      if (signedIn) {
        return location == Routes.access ? null : Routes.access;
      }
      if (location == Routes.access) {
        return connected ? Routes.signIn : Routes.connect;
      }
      if (location == Routes.signIn && !connected) return Routes.connect;
      return null;
    },
    routes: [
      GoRoute(
        path: Routes.connect,
        builder: (context, state) => ConnectScreen(
          session: widget.session,
          onConnected: () => _router.go(Routes.signIn),
          onSignedIn: () => _router.go(Routes.access),
        ),
      ),
      GoRoute(
        path: Routes.signIn,
        builder: (context, state) => SignInScreen(
          session: widget.session,
          onSignedIn: () => _router.go(Routes.access),
          onChangeSite: () => _router.go(Routes.connect),
        ),
      ),
      GoRoute(
        path: Routes.access,
        builder: (context, state) => AccessScreen(
          session: widget.session,
          onSignedOut: () => _router.go(Routes.connect),
        ),
      ),
    ],
  );

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'webtrees',
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    routerConfig: _router,
    debugShowCheckedModeBanner: false,
  );
}

/// Every route in the app.
abstract final class Routes {
  static const String connect = '/connect';
  static const String signIn = '/sign-in';
  static const String access = '/access';
}
