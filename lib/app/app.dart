import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/session_manager.dart';
import '../data/settings_store.dart';
import '../data/stock/media_cache.dart';
import '../data/stock/records_repository.dart';
import '../features/access/access_screen.dart';
import '../features/auth/sign_in_screen.dart';
import '../features/browse/person_screen.dart';
import '../features/browse/search_screen.dart';
import '../features/connect/connect_screen.dart';
import '../l10n/app_localizations.dart';
import 'theme.dart';

/// The application shell.
class WebtreesMobileApp extends StatefulWidget {
  const WebtreesMobileApp({
    required this.session,
    required this.settings,
    super.key,
  });

  final SessionManager session;
  final SettingsStore settings;

  @override
  State<WebtreesMobileApp> createState() => _WebtreesMobileAppState();
}

class _WebtreesMobileAppState extends State<WebtreesMobileApp> {
  /// Shared by every browsing screen, and emptied the moment nobody is signed
  /// in. Family photographs are private to the account that fetched them, so
  /// the cache must not outlive the session that filled it.
  final MediaCache _media = MediaCache();

  /// A repository bound to the current signed-in client.
  ///
  /// Built per navigation rather than held, because the client is replaced
  /// whenever the app reconnects or signs in again — a cached repository would
  /// go on talking through a closed one.
  RecordsRepository get _records => RecordsRepository(
    widget.session.client,
    version: widget.session.instance?.version,
    mediaCache: _media,
  );

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_forgetImagesWhenSignedOut);
  }

  void _forgetImagesWhenSignedOut() {
    if (!widget.session.isSignedIn) _media.clear();
  }

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
        // Any signed-in screen is fine; only a signed-out one is not.
        return location == Routes.connect || location == Routes.signIn
            ? Routes.access
            : null;
      }
      if (location != Routes.connect && location != Routes.signIn) {
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
          settings: widget.settings,
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
          settings: widget.settings,
          onSignedOut: () => _router.go(Routes.connect),
          onBrowseTree: (tree) => _router.go(Routes.searchIn(tree)),
        ),
      ),
      GoRoute(
        path: Routes.search,
        builder: (context, state) {
          final tree = state.pathParameters['tree']!;
          return SearchScreen(
            session: widget.session,
            records: _records,
            tree: tree,
            onOpenPerson: (xref) => _router.go(Routes.personIn(tree, xref)),
          );
        },
      ),
      GoRoute(
        path: Routes.person,
        builder: (context, state) {
          final tree = state.pathParameters['tree']!;
          return PersonScreen(
            session: widget.session,
            records: _records,
            tree: tree,
            xref: state.pathParameters['xref']!,
            // Pushed rather than replaced, so walking up a family tree can be
            // walked back down again.
            onOpenPerson: (xref) => _router.push(Routes.personIn(tree, xref)),
          );
        },
      ),
    ],
  );

  @override
  void dispose() {
    widget.session.removeListener(_forgetImagesWhenSignedOut);
    _media.clear();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.settings,
    builder: (context, _) {
      // The theme is built per-locale, because Arabic needs different letter
      // spacing and leading from Latin (see AppTheme). So the resolved
      // locale has to be known here, not left to MaterialApp to work out.
      final locale = widget.settings.resolve(
        View.of(context).platformDispatcher.locale,
      );

      return MaterialApp.router(
        onGenerateTitle: (context) => AppText.of(context).appTitle,
        theme: AppTheme.light(locale),
        darkTheme: AppTheme.dark(locale),
        themeMode: widget.settings.themeMode,
        locale: widget.settings.locale,
        localizationsDelegates: AppText.localizationsDelegates,
        supportedLocales: SettingsStore.supportedLocales,
        routerConfig: _router,
        debugShowCheckedModeBanner: false,
      );
    },
  );
}

/// Every route in the app.
abstract final class Routes {
  static const String connect = '/connect';
  static const String signIn = '/sign-in';
  static const String access = '/access';
  static const String search = '/tree/:tree';
  static const String person = '/tree/:tree/person/:xref';

  static String searchIn(String tree) => '/tree/${Uri.encodeComponent(tree)}';

  static String personIn(String tree, String xref) =>
      '${searchIn(tree)}/person/${Uri.encodeComponent(xref)}';
}
