import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/session_manager.dart';
import '../data/settings_store.dart';
import '../data/stock/charts_repository.dart';
import '../data/stock/media_cache.dart';
import '../data/stock/records_repository.dart';
import '../domain/charts.dart';
import '../features/access/access_screen.dart';
import '../features/auth/sign_in_screen.dart';
import '../features/browse/person_screen.dart';
import '../features/browse/search_screen.dart';
import '../features/charts/chart_screen.dart';
import '../features/charts/relationship_screen.dart';
import '../features/charts/statistics_screen.dart';
import '../features/charts/timeline_screen.dart';
import '../features/connect/connect_screen.dart';
import '../features/launch/launch_screen.dart';
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

  /// Charts are read through the same client, and the same reasoning: it is
  /// replaced whenever the app reconnects, so nothing may hold one.
  ChartsRepository get _charts => ChartsRepository(
    widget.session.client,
    version: widget.session.instance?.version,
  );

  /// Whether the app has already walked into the account's only tree.
  ///
  /// Once is helpful; every time would trap the reader, because the account
  /// screen would bounce them straight back out of it.
  bool _openedOnlyTree = false;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_onSessionChanged);
    widget.settings.addListener(_onSettingsChanged);
  }

  void _onSessionChanged() {
    if (widget.session.isSignedIn) return;
    // Family photographs must not outlive the account that fetched them, and
    // the next account may not see the same single tree.
    _media.clear();
    _openedOnlyTree = false;
  }

  /// Keeps the server rendering in the language the app is reading in.
  ///
  /// webtrees writes the dates, month names and fact labels, and it does so in
  /// the language held in its own session — so a language change here has to
  /// travel to the server or half the screen stays in the old one.
  void _onSettingsChanged() {
    unawaited(widget.session.syncContentLanguage());
  }

  void _openOnlyTree(String name, String? title) {
    if (_openedOnlyTree) return;
    _openedOnlyTree = true;
    // Replaces rather than stacks: with one tree this *is* the home screen,
    // and a back gesture should leave the app, not return to a list of one.
    _router.go(Routes.searchIn(name), extra: title);
  }

  late final GoRouter _router = GoRouter(
    initialLocation: Routes.launch,
    // Rebuilds the routing decision whenever the session changes, so an
    // expired session cannot leave a signed-out user on a signed-in screen.
    refreshListenable: widget.session,
    redirect: (context, state) {
      final signedIn = widget.session.isSignedIn;
      final connected = widget.session.instance != null;
      final location = state.matchedLocation;

      if (signedIn) {
        // Any signed-in screen is fine; only a signed-out one is not.
        return location == Routes.connect ||
                location == Routes.signIn ||
                location == Routes.launch
            ? Routes.access
            : null;
      }
      // The launch screen is deciding whether there is anything to resume, so
      // nothing may move the app off it until it says so.
      if (location == Routes.launch) return null;
      if (location != Routes.connect && location != Routes.signIn) {
        return connected ? Routes.signIn : Routes.connect;
      }
      if (location == Routes.signIn && !connected) return Routes.connect;
      return null;
    },
    routes: [
      GoRoute(
        path: Routes.launch,
        builder: (context, state) => LaunchScreen(
          session: widget.session,
          // A resume that got as far as identifying the site — a password
          // that has stopped working, an unlock declined — has nothing left
          // to ask but the password, so it should not ask for the address
          // again as well.
          onNothingToResume: () => _router.go(
            widget.session.instance == null ? Routes.connect : Routes.signIn,
          ),
        ),
      ),
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
          // Stacked, so a reader who chose one of several trees can go back
          // to the list with the system back gesture.
          onBrowseTree: (name, title) =>
              _router.push(Routes.searchIn(name), extra: title),
          onOnlyTree: _openOnlyTree,
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
            // Only ever a label. The route still carries the tree's name,
            // so a link that arrives without a title still works.
            title: state.extra as String?,
            onOpenPerson: (xref) => _router.push(Routes.personIn(tree, xref)),
            onShowAccount: () => _router.push(Routes.access),
            onShowStatistics: () => _router.push(Routes.statisticsIn(tree)),
          );
        },
        routes: [
          GoRoute(
            path: Routes.statisticsUnderTree,
            builder: (context, state) => StatisticsScreen(
              session: widget.session,
              records: _records,
              charts: _charts,
              tree: state.pathParameters['tree']!,
            ),
          ),
          // Nested, so opening a person by URL still puts the search screen
          // underneath them. As siblings these two shared no stack, and the
          // first back gesture left the app instead of returning to the
          // search results.
          GoRoute(
            path: Routes.personUnderSearch,
            builder: (context, state) {
              final tree = state.pathParameters['tree']!;
              return PersonScreen(
                session: widget.session,
                records: _records,
                settings: widget.settings,
                tree: tree,
                xref: state.pathParameters['xref']!,
                // Pushed rather than replaced, so walking up a family tree
                // can be walked back down again.
                onOpenPerson: (xref) =>
                    _router.push(Routes.personIn(tree, xref)),
                // A relationship is not a shape of a family but a path
                // between two of them, and it needs a second person before
                // there is anything to draw — so it has a screen of its own.
                onOpenChart: (kind) => _router.push(switch (kind) {
                  // Neither of these is a shape of a family: one is a path
                  // between two people, the other a life against a scale.
                  ChartKind.relationship => Routes.relationshipIn(
                    tree,
                    state.pathParameters['xref']!,
                  ),
                  ChartKind.timeline => Routes.timelineIn(
                    tree,
                    state.pathParameters['xref']!,
                  ),
                  _ => Routes.chartIn(
                    tree,
                    state.pathParameters['xref']!,
                    kind,
                  ),
                }),
              );
            },
            routes: [
              GoRoute(
                path: Routes.timelineUnderPerson,
                builder: (context, state) => TimelineScreen(
                  session: widget.session,
                  records: _records,
                  charts: _charts,
                  tree: state.pathParameters['tree']!,
                  xref: state.pathParameters['xref']!,
                ),
              ),
              GoRoute(
                path: Routes.relationshipUnderPerson,
                builder: (context, state) {
                  final tree = state.pathParameters['tree']!;
                  return RelationshipScreen(
                    session: widget.session,
                    records: _records,
                    charts: _charts,
                    tree: tree,
                    xref: state.pathParameters['xref']!,
                    onOpenPerson: (xref) =>
                        _router.push(Routes.personIn(tree, xref)),
                  );
                },
              ),
              // Nested again: a chart is opened from a person, and closing it
              // should put that person back on screen.
              GoRoute(
                path: Routes.chartUnderPerson,
                builder: (context, state) {
                  final tree = state.pathParameters['tree']!;
                  final xref = state.pathParameters['xref']!;
                  final kind = ChartKind.values.firstWhere(
                    (candidate) =>
                        candidate.name == state.pathParameters['kind'],
                    orElse: () => ChartKind.ancestors,
                  );

                  return ChartScreen(
                    session: widget.session,
                    records: _records,
                    charts: _charts,
                    tree: tree,
                    xref: xref,
                    kind: kind,
                    onOpenPerson: (xref) =>
                        _router.push(Routes.personIn(tree, xref)),
                    // The same chart, drawn around somebody else: how a
                    // reader walks a tree without leaving the chart.
                    onOpenChart: (xref) =>
                        _router.push(Routes.chartIn(tree, xref, kind)),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    ],
  );

  @override
  void dispose() {
    widget.session.removeListener(_onSessionChanged);
    widget.settings.removeListener(_onSettingsChanged);
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
  /// Where every launch starts: resume the last site, or ask for one.
  static const String launch = '/';

  static const String connect = '/connect';
  static const String signIn = '/sign-in';
  static const String access = '/access';
  static const String search = '/tree/:tree';

  /// Declared relative to [search], which is what makes a person's page sit
  /// on top of the search results in the navigation stack.
  static const String personUnderSearch = 'person/:xref';

  /// What a site says about the whole tree, rather than about anybody in it.
  static const String statisticsUnderTree = 'statistics';

  /// Declared relative to the person, for the same reason.
  static const String chartUnderPerson = 'chart/:kind';
  static const String relationshipUnderPerson = 'relationship';
  static const String timelineUnderPerson = 'timeline';

  static String searchIn(String tree) => '/tree/${Uri.encodeComponent(tree)}';

  static String personIn(String tree, String xref) =>
      '${searchIn(tree)}/person/${Uri.encodeComponent(xref)}';

  static String chartIn(String tree, String xref, ChartKind kind) =>
      '${personIn(tree, xref)}/chart/${kind.name}';

  static String relationshipIn(String tree, String xref) =>
      '${personIn(tree, xref)}/relationship';

  static String timelineIn(String tree, String xref) =>
      '${personIn(tree, xref)}/timeline';

  static String statisticsIn(String tree) => '${searchIn(tree)}/statistics';
}
