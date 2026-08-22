import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/errors.dart';
import '../../data/session_manager.dart';
import '../../data/stock/records_repository.dart';
import '../../domain/records.dart';
import '../../l10n/app_localizations.dart';
import '../shared/bidi.dart';
import '../shared/message_panel.dart';
import '../shared/messages.dart';
import 'authenticated_image.dart';

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
    this.title,
    super.key,
  });

  final SessionManager session;
  final RecordsRepository records;
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

  /// Rises with each search so a slow earlier reply cannot overwrite a newer
  /// one — typing quickly otherwise leaves the wrong names on screen.
  int _generation = 0;

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
    if (query.trim().isEmpty) {
      setState(() {
        _results = const [];
        _error = null;
        _hasSearched = false;
      });
      return;
    }

    final generation = ++_generation;
    setState(() {
      _searching = true;
      _error = null;
    });

    try {
      final page = await widget.session.withSession(
        () => widget.records.search(widget.tree, query),
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _results = page.people;
        _searching = false;
        _hasSearched = true;
      });
    } on WebtreesError catch (problem) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = problem;
        _searching = false;
        _hasSearched = true;
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
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final person = _results[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            leading: AuthenticatedImage(
              url: person.thumbnailUrl,
              records: widget.records,
              name: person.name,
              size: 48,
            ),
            title: Text(person.name),
            // Isolated, or the Arabic layout around it reads 1875–1940 back
            // to front and the person dies before they are born.
            subtitle: person.lifespan == null
                ? null
                : Text(ltrRun(person.lifespan)),
            onTap: () => widget.onOpenPerson(person.xref),
          ),
        );
      },
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
