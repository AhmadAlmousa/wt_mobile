import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/errors.dart';
import '../../data/session_manager.dart';
import '../../data/stock/records_repository.dart';
import '../../domain/records.dart';
import '../shared/message_panel.dart';
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
    super.key,
  });

  final SessionManager session;
  final RecordsRepository records;
  final String tree;
  final void Function(String xref) onOpenPerson;

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
    return Scaffold(
      appBar: AppBar(title: Text(widget.tree)),
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
                  labelText: 'Search for a person',
                  hintText: 'A name, or a record id such as I42',
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
    final error = _error;
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: MessagePanel.error(error.message),
      );
    }

    if (_results.isEmpty) {
      return _EmptyState(
        // Three different silences, and saying which one it is saves the user
        // guessing whether the app is broken.
        message: !_hasSearched
            ? 'Type a name to search this family tree.'
            : _searching
            ? 'Searching…'
            : 'Nobody matched that name. Try a different spelling, or part '
                  'of the name.',
      );
    }

    return ListView.builder(
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final person = _results[index];
        return ListTile(
          leading: AuthenticatedImage(
            url: person.thumbnailUrl,
            records: widget.records,
            size: 44,
          ),
          title: Text(person.name),
          subtitle: person.lifespan == null ? null : Text(person.lifespan!),
          onTap: () => widget.onOpenPerson(person.xref),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ),
  );
}
