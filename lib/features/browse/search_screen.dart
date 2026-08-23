import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/errors.dart';
import '../../data/session_manager.dart';
import '../../data/transport.dart';
import '../../domain/charts.dart';
import '../../domain/records.dart';
import '../../l10n/app_localizations.dart';
import '../shared/message_panel.dart';
import '../shared/messages.dart';
import '../shared/person_tile.dart';

/// Finds people in one tree by name.
///
/// Search, not a directory. The only JSON endpoint a stock webtrees exposes
/// refuses an empty query, and no other route pages through a whole tree
/// cheaply — so the screen asks for a name rather than pretending to offer a
/// browsable list it cannot fill.
class SearchScreen extends StatefulWidget {
  const SearchScreen({
    required this.session,
    required this.records,
    required this.tree,
    required this.onOpenPerson,
    required this.onShowAccount,
    required this.onShowStatistics,
    this.title,
    super.key,
  });

  final SessionManager session;
  final RecordsTransport records;
  final String tree;

  /// What the family calls this tree, when the app was told.
  ///
  /// `tree` is the identifier webtrees routes on — often `main` — which is a
  /// poor name for what is usually the app's home screen.
  final String? title;
  final void Function(String xref) onOpenPerson;

  /// Opens the account screen.
  ///
  /// An account with one tree comes straight here, so this is the only route
  /// back to what the app knows about the site, the role and the session.
  final VoidCallback onShowAccount;

  /// Opens what the site says about the tree as a whole.
  final VoidCallback onShowStatistics;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _query = TextEditingController();

  Timer? _debounce;
  List<PersonRef> _results = const [];
  WebtreesError? _error;
  bool _searching = false;
  bool _hasSearched = false;

  /// What the results on screen are answers to.
  ///
  /// Held because a further page has to repeat the query: webtrees' own
  /// `nextUrl` is built without it, so following that link would page through
  /// an empty search.
  String _searchedFor = '';

  /// The last page fetched, counting from one as webtrees does.
  int _page = 1;
  bool _hasMore = false;
  bool _loadingMore = false;

  /// A failure while fetching a *further* page, which must not throw away the
  /// results already on screen.
  WebtreesError? _moreError;

  /// Rises with each search so a slow earlier reply cannot overwrite a newer
  /// one — typing quickly otherwise leaves the wrong names on screen.
  int _generation = 0;

  /// Whether this site publishes statistics for the tree.
  ///
  /// Read from the tree's own page, once, because that is where webtrees puts
  /// the link — and a button for a page the site does not publish is a promise
  /// the next tap breaks.
  bool _hasStatistics = false;

  @override
  void initState() {
    super.initState();
    unawaited(_findTreeCharts());
  }

  Future<void> _findTreeCharts() async {
    try {
      final offered = await widget.session.withSession(
        () => widget.records.treeCharts(widget.tree),
      );
      if (!mounted) return;
      setState(() {
        _hasStatistics = offered.containsKey(ChartKind.statistics);
      });
    } on WebtreesError {
      // Nothing is lost: the tree still browses, it simply offers no
      // statistics button.
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    // Every keystroke would be a request against someone else's server.
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(value));
  }

  Future<void> _search(String query) async {
    // Submitting from the keyboard leaves the debounce still pending, and
    // letting it fire would repeat the same search a moment later — a second
    // request against someone else's server, and one that throws away any
    // further pages the reader had asked for.
    _debounce?.cancel();

    if (query.trim().isEmpty) {
      setState(() {
        _results = const [];
        _error = null;
        _hasSearched = false;
        _hasMore = false;
      });
      return;
    }

    final generation = ++_generation;
    setState(() {
      _searching = true;
      _error = null;
      _moreError = null;
      _searchedFor = query;
      _page = 1;
    });

    try {
      final page = await widget.session.withSession(
        () => widget.records.search(widget.tree, query),
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _results = page.people;
        _hasMore = page.hasMore;
        _searching = false;
        _hasSearched = true;
      });
    } on WebtreesError catch (problem) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = problem;
        _hasMore = false;
        _searching = false;
        _hasSearched = true;
      });
    }
  }

  /// Fetches the next 50 results and adds them to the ones on screen.
  ///
  /// A common surname matches far more people than one page holds, and
  /// webtrees says exactly whether more exist rather than leaving it to be
  /// guessed from a full page.
  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;

    final generation = _generation;
    setState(() {
      _loadingMore = true;
      _moreError = null;
    });

    try {
      final next = await widget.session.withSession(
        () => widget.records.search(widget.tree, _searchedFor, page: _page + 1),
      );
      if (!mounted || generation != _generation) return;

      // Someone recorded under two names is two rows in the search webtrees
      // runs, and it only removes those duplicates within one page — so the
      // same person can arrive again on the next.
      final seen = _results.map((person) => person.xref).toSet();
      setState(() {
        _results = [
          ..._results,
          ...next.people.where((person) => seen.add(person.xref)),
        ];
        _page += 1;
        _hasMore = next.hasMore;
        _loadingMore = false;
      });
    } on WebtreesError catch (problem) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _moreError = problem;
        _loadingMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? widget.tree),
        actions: [
          if (_hasStatistics)
            IconButton(
              icon: const Icon(Icons.insights_outlined),
              tooltip: text.statistics,
              onPressed: widget.onShowStatistics,
            ),
          IconButton(
            icon: const Icon(Icons.account_circle_outlined),
            tooltip: text.yourAccount,
            onPressed: widget.onShowAccount,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _query,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  labelText: text.searchForAPerson,
                  hintText: text.searchHint,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                ),
                onChanged: _onChanged,
                onSubmitted: _search,
              ),
            ),
            Expanded(child: _body(context)),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final text = AppText.of(context);
    final error = _error;
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: MessagePanel.error(error.localized(text)),
      );
    }

    if (_results.isEmpty) {
      return _EmptyState(
        // Three different silences, and saying which one it is saves the user
        // guessing whether the app is broken.
        message: !_hasSearched
            ? text.searchPrompt
            : _searching
            ? text.searching
            : text.noMatches,
        icon: !_hasSearched
            ? Icons.search
            : _searching
            ? Icons.hourglass_empty
            : Icons.person_search_outlined,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      // One row beyond the results when the site says it has more, which is
      // where the reader asks for them.
      itemCount: _results.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _results.length) return _moreFooter(context);

        final person = _results[index];
        // A search row is the one place the app draws somebody without
        // knowing their sex: webtrees' autocomplete sends a name, a lifespan
        // and sometimes a photograph, and nothing else. Opening them answers
        // it; asking the server per row would be a request each.
        return PersonTile(
          person: person,
          records: widget.records,
          onOpen: () => widget.onOpenPerson(person.xref),
        );
      },
    );
  }

  /// The row that asks for the next page, or explains why it could not.
  Widget _moreFooter(BuildContext context) {
    final text = AppText.of(context);
    final problem = _moreError;

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Column(
        children: [
          if (problem != null) ...[
            MessagePanel.error(problem.localized(text)),
            const SizedBox(height: 12),
          ],
          if (_loadingMore)
            const Padding(
              padding: EdgeInsets.all(8),
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            OutlinedButton(
              onPressed: _loadMore,
              child: Text(text.showMoreResults),
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message, required this.icon});

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 32, color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
