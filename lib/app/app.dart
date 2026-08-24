import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/capabilities.dart';
import '../data/local/local_charts.dart';
import '../data/local/offline.dart';
import '../data/local/records_page.dart';
import '../data/local/tree_store.dart';
import '../data/module/module_api.dart';
import '../data/module/module_charts.dart';
import '../data/module/module_records.dart';
import '../data/session_manager.dart';
import '../data/settings_store.dart';
import '../data/stock/charts_repository.dart';
import '../data/stock/media_cache.dart';
import '../data/stock/records_repository.dart';
import '../data/transport.dart';
import '../domain/access.dart';
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
    required this.treeStore,
    super.key,
  });

  final SessionManager session;
  final SettingsStore settings;

  /// This device's copy of a tree, and the policy around it.
  ///
  /// Owned above the shell so it survives navigation and is disposed exactly
  /// once. The shell binds it to whichever tree is open and hands the composer
  /// a transport over it — but only once `TreeStore` says the copy is
  /// complete, which is the whole of the staleness rule `sync_eval.md` §10
  /// asks for.
  final TreeStore treeStore;

  @override
  State<WebtreesMobileApp> createState() => _WebtreesMobileAppState();
}

class _WebtreesMobileAppState extends State<WebtreesMobileApp> {
  /// Shared by every browsing screen, and emptied the moment nobody is signed
  /// in. Family photographs are private to the account that fetched them, so
  /// the cache must not outlive the session that filled it.
  final MediaCache _media = MediaCache();

  /// What the current site's optional module can do, if it has one.
  ///
  /// Probed once per connection and never required: `ModuleCapabilities.none`
  /// — a site with no module, which is the ordinary case — selects the stock
  /// transport for everything, and that is the floor the app is built on.
  ModuleCapabilities _capabilities = ModuleCapabilities.none;

  /// A repository bound to the current signed-in client.
  ///
  /// Built per navigation rather than held, because the client is replaced
  /// whenever the app reconnects or signs in again — a cached repository would
  /// go on talking through a closed one.
  RecordsTransport get _records {
    // No site to ask. The store *is* the app now, and the things it cannot
    // hold — photographs, the site's own statistics — say so rather than
    // failing as though something broke.
    if (widget.session.isOffline) {
      final local = widget.treeStore.transportOver(
        () => const OfflineRecordsTransport(),
      );
      return local ?? const OfflineRecordsTransport();
    }

    // Composed twice, over the same two sources: once as the thing the store
    // falls back to for the bytes and the tree-level charts it cannot hold,
    // and once as the thing the app reads. `local` is null unless a complete
    // copy for *this* reader is open — everything that decides that lives in
    // `TreeStore`, so by the time it reaches the composer it is decided.
    return _composed(local: widget.treeStore.transportOver(_composed));
  }

  /// The module where this site offers it, the site's own pages where it does
  /// not, and optionally this device's copy above both.
  CapabilityRecordsTransport _composed({RecordsTransport? local}) {
    final client = widget.session.client;
    final version = widget.session.instance?.version;

    return CapabilityRecordsTransport(
      stock: RecordsRepository(client, version: version, mediaCache: _media),
      module: _capabilities.isPresent
          ? ModuleRecordsTransport(client, mediaCache: _media)
          : null,
      local: local,
      capabilities: _capabilities,
    );
  }

  /// Charts are read through the same client, and the same reasoning: it is
  /// replaced whenever the app reconnects, so nothing may hold one.
  ChartsTransport get _charts {
    // Offline the only charts that can be drawn are the ones this device can
    // walk out of its own copy; everything else says so rather than issuing a
    // request that cannot go anywhere.
    final online = widget.session.isOffline
        ? const OfflineChartsTransport()
        : CapabilityChartsTransport(
            stock: ChartsRepository(
              widget.session.client,
              version: widget.session.instance?.version,
            ),
            module: _capabilities.isPresent
                ? ModuleChartsTransport(widget.session.client)
                : null,
          );

    // Layered above rather than beside: it looks at the handle, draws the ones
    // it minted, and hands everything else on. Which is the same rule
    // `CapabilityChartsTransport` already keeps — a handle is only meaningful
    // to whoever made it.
    final store = widget.treeStore.store;
    final tree = widget.treeStore.tree;
    if (store == null || tree == null || !widget.treeStore.isReadable) {
      return online;
    }

    return LocalChartsTransport(store: store, tree: tree, online: online);
  }

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
    widget.treeStore.addListener(_onStoreChanged);
  }

  void _onSessionChanged() {
    if (widget.session.isSignedIn) {
      unawaited(_probeModule());
      return;
    }
    // Going offline is not losing a session: the copy stays open and the
    // reader stays where they were. Clearing here would throw away the
    // access summary `_openOffline` has just read out of the store's stamp.
    if (widget.session.isOffline) return;
    // Family photographs must not outlive the account that fetched them, and
    // the next account may not see the same single tree.
    _media.clear();
    _openedOnlyTree = false;
    _capabilities = ModuleCapabilities.none;
    _access = null;
    _boundTree = null;
  }

  /// The reader signed out, deliberately.
  ///
  /// Which is **not** the same as the session ending, and the difference is
  /// the whole reason this is a separate path. webtrees expires a session on
  /// an idle timer with no warning, and `SessionManager.withSession` re-signs
  /// in silently; where it cannot, the app is signed out through no decision
  /// of the reader's. Destroying the copy there would mean a ~5 MB
  /// re-download every time a phone sat in a pocket too long.
  ///
  /// A deliberate sign-out is different, and `sync_eval.md` §6 #2 is about
  /// that one: the store makes yesterday's permissions durable, so leaving has
  /// to take the tree with it — the file *and* its key, because a deleted key
  /// alone leaves ciphertext, which is close to destruction and is not it.
  ///
  /// An expired session leaves the copy where it is, which is safe: it is
  /// encrypted under a key belonging to one account, so the next reader either
  /// is that account — and inherits their own copy — or cannot open it at all.
  void _onSignedOut() {
    _access = null;
    _boundTree = null;
    unawaited(widget.treeStore.destroy());
    _router.go(Routes.connect);
  }

  /// Opens this device's copy when the site could not be reached.
  ///
  /// Returns whether there was one. False means the ordinary "ask them to
  /// sign in" path, because a reader with no copy and no network genuinely
  /// cannot be shown anything.
  Future<bool> _openOffline() async {
    final saved = (await widget.session.savedConnections()).firstOrNull;
    if (saved == null) return false;

    final state = await widget.treeStore.bindOffline(saved);
    if (state == null) return false;

    widget.session.goOffline(saved);
    _boundTree = state.tree;
    // The store's own stamp says who the reader is and what they may do, which
    // is what an access probe would have gone to the site to ask.
    _access = AccessSummary(
      account: Account(
        username: state.username,
        // The real name was learned on a previous online visit and stored
        // against the connection, so the account card reads the same offline
        // as it does on.
        realName: saved.displayName,
      ),
      trees: [
        for (final tree in await widget.treeStore.storedTrees())
          TreeAccess(
            name: tree.tree,
            role: TreeRole.values.firstWhere(
              (candidate) => candidate.name == tree.role,
              orElse: () => TreeRole.memberOrVisitor,
            ),
          ),
      ],
      isAdministrator: false,
    );

    if (mounted) {
      setState(() {});
      _router.go(Routes.searchIn(state.tree));
    }
    return true;
  }

  /// Tries the site again after a spell of reading this device's copy.
  ///
  /// Back to the launch screen rather than straight at a sign-in form: that
  /// screen already knows how to resume a stored password, and if the network
  /// is still down it will land back here, which is the right outcome.
  void _reconnect() {
    widget.session.goOnline();
    _router.go(Routes.launch);
  }

  /// The copy became readable, or stopped being. Rebuilds the routes so the
  /// composer is handed the store the moment it is worth reading — otherwise
  /// a sync that finished while the reader was looking at a screen would not
  /// take effect until they navigated away from it.
  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  /// What the reader may see, as of the last time the account screen ran.
  AccessSummary? _access;

  /// Which tree the store is currently bound to, so binding is not attempted
  /// on every rebuild of the search route.
  String? _boundTree;

  void _onAccessSummary(AccessSummary summary) {
    _access = summary;
    final bound = _boundTree;
    // A role can change between sign-ins, and the copy is stamped with the old
    // one. Re-binding is how the stamp gets re-checked, and `TreeSync` drops
    // the copy when it no longer matches.
    if (bound != null) unawaited(_bindStore(bound));
  }

  /// Points the store at [tree] and lets it decide whether to fill.
  ///
  /// Everything about *when* is `TreeStore`'s: on wifi it fills in the
  /// background on first use, on a cellular network it waits and says so.
  /// This method only supplies the four things that identify a copy — who,
  /// which tree, which language, which module — and the wire to fill it from.
  Future<void> _bindStore(String tree) async {
    // Offline the copy is already open and there is no wire to fill it from.
    // Switching between trees this device holds needs no session at all.
    if (widget.session.isOffline) {
      _boundTree = tree;
      await widget.treeStore.openStoredTree(tree);
      return;
    }

    final connection = widget.session.connection;
    final access = _access;
    if (connection == null || access == null) return;

    // Nothing to sync from. A site with no module, or one running a module
    // older than the sync wire, keeps working exactly as it did — which is the
    // floor this whole project stands on.
    if (!_capabilities.has(Capability.records)) return;

    final entry = access.trees.where((each) => each.name == tree);
    if (entry.isEmpty) return;

    _boundTree = tree;

    await widget.treeStore.bind(
      connection: connection,
      tree: entry.first,
      // The same tag the session asks the server to render in. It is half the
      // stamp: every human-readable string in the store — fact labels, dates
      // in six calendars, place names — was written by the server in one
      // language, and a reader who switches is owed a different copy rather
      // than a translated one (`sync_eval.md` §7).
      language: SettingsStore.webtreesLanguageTag(
        widget.settings.resolve(PlatformDispatcher.instance.locale),
      ),
      moduleVersion: _capabilities.moduleVersion,
      source: ModuleSyncSource(ModuleApi(widget.session.client)),
    );

    await widget.treeStore.catchUp();
  }

  /// Asks the site whether it runs the mobile API module.
  ///
  /// One cheap request per sign-in, and nothing waits for it: until it answers
  /// every screen reads HTML, which is what it would do on a site with no
  /// module at all. A failure here is not an error — it is the ordinary case.
  Future<void> _probeModule() async {
    if (_probing) return;
    _probing = true;

    try {
      final found = await ModuleCapabilities.probe(widget.session.client);
      if (mounted && found.isPresent) setState(() => _capabilities = found);
      // The capability probe and the access summary can land in either order,
      // and the store needs both. Whichever is second does the binding.
      final bound = _boundTree;
      if (bound != null) unawaited(_bindStore(bound));
    } on Object {
      // Any failure means "no module", which is the default already in force.
    } finally {
      _probing = false;
    }
  }

  bool _probing = false;

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

      // Reading this device's copy is as good as being signed in, as far as
      // *where the reader may be* is concerned. The difference is what each
      // screen can answer, and each screen says so itself.
      if (signedIn || widget.session.isOffline) {
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
          onOfflineInstead: _openOffline,
        ),
      ),
      GoRoute(
        path: Routes.connect,
        builder: (context, state) => ConnectScreen(
          session: widget.session,
          settings: widget.settings,
          onConnected: () => _router.go(Routes.signIn),
          onSignedIn: () => _router.go(Routes.access),
          onReadOffline: _openOffline,
        ),
      ),
      GoRoute(
        path: Routes.signIn,
        builder: (context, state) => SignInScreen(
          session: widget.session,
          onSignedIn: () => _router.go(Routes.access),
          onChangeSite: () => _router.go(Routes.connect),
          onReadOffline: _openOffline,
        ),
      ),
      GoRoute(
        path: Routes.access,
        builder: (context, state) => AccessScreen(
          session: widget.session,
          settings: widget.settings,
          capabilities: _capabilities,
          offlineSummary: widget.session.isOffline ? _access : null,
          onSignedOut: _onSignedOut,
          // Stacked, so a reader who chose one of several trees can go back
          // to the list with the system back gesture.
          onBrowseTree: (name, title) =>
              _router.push(Routes.searchIn(name), extra: title),
          onOnlyTree: _openOnlyTree,
          onAccessSummary: _onAccessSummary,
          treeStore: widget.treeStore,
        ),
      ),
      GoRoute(
        path: Routes.search,
        builder: (context, state) {
          final tree = state.pathParameters['tree']!;
          // Opening a tree is what makes a copy of it worth having, and this
          // is the one place every route into a tree passes through — a
          // pushed card, the walk into an only tree, and a restored deep
          // link alike. Guarded on the tree it is already bound to, so a
          // rebuild costs nothing.
          if (_boundTree != tree) unawaited(_bindStore(tree));

          return SearchScreen(
            session: widget.session,
            records: _records,
            treeStore: widget.treeStore,
            onReconnect: _reconnect,
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
                    settings: widget.settings,
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
    widget.treeStore.removeListener(_onStoreChanged);
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
