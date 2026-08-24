import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/errors.dart';
import '../../data/session_manager.dart';
import '../../data/transport.dart';
import '../../domain/charts.dart';
import '../../domain/records.dart';
import '../../l10n/app_localizations.dart';
import '../shared/bidi.dart';
import '../shared/chart_header_title.dart';
import '../shared/message_panel.dart';
import '../shared/messages.dart';
import '../shared/person_tile.dart';
import 'chart_canvas.dart';
import 'chart_layout.dart';
import 'relationship_layout.dart';
import 'relationship_modes.dart';
import 'relationship_path_view.dart';

/// How two people in a tree are related.
///
/// The one question a family tree gets asked more than any other, and the one
/// the app cannot answer for itself: working it out means walking a graph the
/// app would have to fetch a record at a time. webtrees already knows, and
/// says so in the reader's language — including distinctions English does not
/// make, where Arabic separates an older brother from a younger one.
///
/// What the app *can* do is ask the question the way a person would. webtrees
/// answers with every path it found; sorting those by which of the subject's
/// own relatives each one leaves through turns a list into "on my mother's
/// side" — see [RelationshipRoutes].
///
/// And it can draw the answer twice. A path down the page says what the link
/// is; a tree says where these people sit in the family. Each is a mode of
/// this screen and each gets the whole body — see [RelationshipView].
class RelationshipScreen extends StatefulWidget {
  const RelationshipScreen({
    required this.session,
    required this.records,
    required this.charts,
    required this.tree,
    required this.xref,
    required this.onOpenPerson,
    super.key,
  });

  final SessionManager session;
  final RecordsTransport records;
  final ChartsTransport charts;
  final String tree;
  final String xref;
  final void Function(String xref) onOpenPerson;

  @override
  State<RelationshipScreen> createState() => _RelationshipScreenState();
}

class _RelationshipScreenState extends State<RelationshipScreen> {
  late Future<IndividualRecord> _person;

  /// The person the comparison starts from, once their record has arrived.
  PersonRef? _subject;

  /// The person to compare with, once the reader has chosen one.
  PersonRef? _other;
  Future<List<RelationshipPath>>? _paths;

  /// Whether to search blood lines only, or `null` to leave the site's own
  /// setting alone. Asking either way is a request webtrees means to answer —
  /// see [ChartsRepository.relationship].
  bool? _bloodOnly;

  RelationshipSide _side = RelationshipSide.closest;

  /// Which of the two drawings is on screen.
  RelationshipView _view = RelationshipView.path;

  /// Which of the paths the tree is drawing, among those the side offers.
  ///
  /// Reset whenever the question changes, because "the second way" means
  /// nothing once the answers are different ones.
  int _way = 0;

  @override
  void initState() {
    super.initState();
    _person = widget.session.withSession(
      () => widget.records.individual(widget.tree, widget.xref),
    );
    // Remembered so the bar can name them while a path is being fetched.
    _person.then((person) {
      if (mounted) setState(() => _subject = person.asReference);
    }).ignore();
  }

  void _compareWith(PersonRef other, IndividualRecord person) {
    setState(() {
      _other = other;
      _side = RelationshipSide.closest;
      _bloodOnly = null;
      _way = 0;
      _search(person);
    });
  }

  /// Asks the site again, with whatever the reader has chosen.
  void _search(IndividualRecord person) {
    final url = person.charts[ChartKind.relationship];
    final other = _other;
    if (url == null || other == null) return;

    _paths = widget.session.withSession(
      () => widget.charts.relationship(
        url,
        from: person.xref,
        to: other.xref,
        bloodLinesOnly: _bloodOnly,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);

    return Scaffold(
      appBar: AppBar(
        title: ChartHeaderTitle(
          title: text.chartRelationship,
          person: _subject,
          records: widget.records,
        ),
      ),
      body: SafeArea(
        child: FutureBuilder<IndividualRecord>(
          future: _person,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final error = snapshot.error;
            if (error != null) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: MessagePanel.error(
                  error is WebtreesError
                      ? error.localized(text)
                      : text.personOpenFailed,
                ),
              );
            }

            final person = snapshot.data!;
            final other = _other;
            if (other == null) {
              return _PersonPicker(
                session: widget.session,
                records: widget.records,
                tree: widget.tree,
                prompt: text.relationshipPick(person.name),
                onPicked: (picked) => _compareWith(picked, person),
              );
            }

            return _Answer(
              paths: _paths!,
              subject: person,
              to: other,
              records: widget.records,
              side: _side,
              onSide: (side) => setState(() {
                _side = side;
                _way = 0;
              }),
              view: _view,
              onView: (view) => setState(() => _view = view),
              way: _way,
              onWay: (way) => setState(() => _way = way),
              onDrawTree: (way) => setState(() {
                _way = way;
                _view = RelationshipView.tree;
              }),
              // The site's own setting is what the app was offered, and what
              // it falls back to; the switch says which of the two is in
              // force, not which one the administrator chose.
              bloodOnly:
                  _bloodOnly ??
                  widget.charts.bloodLinesOnly(
                    person.charts[ChartKind.relationship] ?? '',
                  ),
              onBloodOnly: (only) => setState(() {
                _bloodOnly = only;
                _side = RelationshipSide.closest;
                _way = 0;
                _search(person);
              }),
              onOpenPerson: widget.onOpenPerson,
              onChooseAgain: () => setState(() {
                _other = null;
                _paths = null;
                _way = 0;
                _view = RelationshipView.path;
              }),
            );
          },
        ),
      ),
    );
  }
}

/// The answer, and the ways of asking for a different one.
class _Answer extends StatelessWidget {
  const _Answer({
    required this.paths,
    required this.subject,
    required this.to,
    required this.records,
    required this.side,
    required this.onSide,
    required this.view,
    required this.onView,
    required this.way,
    required this.onWay,
    required this.onDrawTree,
    required this.bloodOnly,
    required this.onBloodOnly,
    required this.onOpenPerson,
    required this.onChooseAgain,
  });

  final Future<List<RelationshipPath>> paths;
  final IndividualRecord subject;
  final PersonRef to;
  final RecordsTransport records;

  final RelationshipSide side;
  final ValueChanged<RelationshipSide> onSide;

  /// Which drawing is on screen, and how the reader changes it.
  final RelationshipView view;
  final ValueChanged<RelationshipView> onView;

  /// Which of the paths the tree draws, among those [side] offers.
  final int way;
  final ValueChanged<int> onWay;

  /// Draw a particular way as a tree — the button beside each relationship.
  final ValueChanged<int> onDrawTree;

  /// Whether the search in force is limited to blood relations.
  final bool bloodOnly;
  final ValueChanged<bool> onBloodOnly;

  final void Function(String xref) onOpenPerson;
  final VoidCallback onChooseAgain;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);

    return FutureBuilder<List<RelationshipPath>>(
      future: paths,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final error = snapshot.error;
        if (error != null) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: MessagePanel.error(
              error is WebtreesError ? error.localized(text) : text.chartFailed,
            ),
          );
        }

        final routes = RelationshipRoutes(
          paths: snapshot.data!,
          subject: subject,
        );
        final chosen = routes.matching(side);

        // The tree draws one path, so it has nothing to draw until there is
        // one — and offering the mode anyway would be a button that leads to
        // an empty screen.
        if (chosen.isEmpty || view == RelationshipView.path) {
          return _AsPath(
            routes: routes,
            chosen: chosen,
            to: to,
            records: records,
            side: side,
            onSide: onSide,
            // With nothing to draw the switch shows the mode on screen and
            // shows it disabled: a control that reads "Tree" over a list of
            // steps would be describing a screen the reader is not looking
            // at. The chosen mode is remembered, so a side that *does* have
            // an answer comes back drawn.
            view: chosen.isEmpty ? RelationshipView.path : view,
            onView: chosen.isEmpty ? null : onView,
            onDrawTree: onDrawTree,
            bloodOnly: bloodOnly,
            onBloodOnly: onBloodOnly,
            onOpenPerson: onOpenPerson,
            onChooseAgain: onChooseAgain,
          );
        }

        return _AsTree(
          // A side the reader has left may hold fewer ways than the one they
          // came from, so the chosen way is clamped rather than trusted.
          path: chosen[way.clamp(0, chosen.length - 1)],
          ways: chosen.length,
          way: way.clamp(0, chosen.length - 1),
          onWay: onWay,
          view: view,
          onView: onView,
          records: records,
          onOpenPerson: onOpenPerson,
        );
      },
    );
  }
}

/// The steps, one under the next — and everything the question can be asked
/// differently by.
class _AsPath extends StatelessWidget {
  const _AsPath({
    required this.routes,
    required this.chosen,
    required this.to,
    required this.records,
    required this.side,
    required this.onSide,
    required this.view,
    required this.onView,
    required this.onDrawTree,
    required this.bloodOnly,
    required this.onBloodOnly,
    required this.onOpenPerson,
    required this.onChooseAgain,
  });

  final RelationshipRoutes routes;
  final List<RelationshipPath> chosen;
  final PersonRef to;
  final RecordsTransport records;

  final RelationshipSide side;
  final ValueChanged<RelationshipSide> onSide;

  final RelationshipView view;

  /// Null when there is nothing to draw, which disables the switch rather
  /// than hiding it — the same rule the sides follow.
  final ValueChanged<RelationshipView>? onView;

  final ValueChanged<int> onDrawTree;

  final bool bloodOnly;
  final ValueChanged<bool> onBloodOnly;

  final void Function(String xref) onOpenPerson;
  final VoidCallback onChooseAgain;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = AppText.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        // Who is being compared with. The subject is already named in
        // the bar, so repeating them here would cost a third of the
        // screen to say what it already says.
        _Comparing(
          // Preferred over the search result the reader picked, which
          // carries no sex: webtrees' autocomplete sends a name, a
          // lifespan and sometimes a photograph, and nothing else.
          person: _asKnown(routes, to),
          records: records,
          onChooseAgain: onChooseAgain,
        ),
        const SizedBox(height: 16),

        _Ways(
          routes: routes,
          side: side,
          onSide: onSide,
          bloodOnly: bloodOnly,
          onBloodOnly: onBloodOnly,
        ),
        const SizedBox(height: 8),

        _ViewSwitch(view: view, onView: onView),
        const SizedBox(height: 16),

        if (routes.isEmpty) ...[
          MessagePanel.warning(text.relationshipNoLink),
          // Two people can be in one tree and not related at all — and on
          // a search limited to blood lines, a marriage is not a link
          // either. Saying which is the difference between an answer and
          // an apparent failure — and here the reader can lift the limit
          // in the row above rather than being told about it.
          if (bloodOnly) ...[
            const SizedBox(height: 12),
            Text(
              text.relationshipBloodOnly,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ] else if (chosen.isEmpty)
          MessagePanel.warning(text.relationshipNoneThisWay)
        else ...[
          // The site's own phrase for the whole relationship. Composing
          // one here would mean inventing kinship terms in two languages,
          // and Arabic makes distinctions English has no word for.
          RelationshipSummary(
            description: chosen.first.description,
            steps: chosen.first.steps.length,
            onDrawTree: () => onDrawTree(0),
          ),
          const SizedBox(height: 16),
          RelationshipPathView(
            path: chosen.first,
            records: records,
            onOpenPerson: onOpenPerson,
          ),

          // A family where cousins marry links two people by more than
          // one line, and each is true.
          if (chosen.length > 1) ...[
            const SizedBox(height: 28),
            Text(
              text.relationshipOtherWays,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            for (final (at, path) in chosen.indexed.skip(1)) ...[
              const SizedBox(height: 12),
              // Beside every other way too, not only the closest: each one
              // is a different shape of family, and the shape is the whole
              // reason to draw it.
              _OtherWayHeader(
                description: path.description,
                onDrawTree: () => onDrawTree(at),
              ),
              RelationshipPathView(
                path: path,
                records: records,
                onOpenPerson: onOpenPerson,
              ),
            ],
          ],
        ],
      ],
    );
  }

  /// [person] as a chart box described them, where any path reached them.
  ///
  /// A path's boxes carry the sex and the death that a search result cannot,
  /// which is what keeps one screen from drawing the same person two ways.
  static PersonRef _asKnown(RelationshipRoutes routes, PersonRef person) {
    for (final path in routes.all) {
      for (final step in path.steps) {
        if (step.person.xref == person.xref) return step.person;
      }
      if (path.from.xref == person.xref) return path.from;
    }
    return person;
  }
}

/// The same steps, placed by generation and joined.
///
/// Given the whole body on purpose. A chart under a column of controls is a
/// picture of a family rather than one anybody can read — the switch back to
/// the path is where the ways of asking live.
class _AsTree extends StatelessWidget {
  const _AsTree({
    required this.path,
    required this.ways,
    required this.way,
    required this.onWay,
    required this.view,
    required this.onView,
    required this.records,
    required this.onOpenPerson,
  });

  final RelationshipPath path;

  /// How many ways this side offers, and which of them is drawn.
  final int ways;
  final int way;
  final ValueChanged<int> onWay;

  final RelationshipView view;
  final ValueChanged<RelationshipView> onView;

  final RecordsTransport records;
  final void Function(String xref) onOpenPerson;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = AppText.of(context);
    final mirrored = Directionality.of(context) == TextDirection.rtl;

    // A site — or a module older than this feature — that never said which
    // way a step goes leaves every box on one row, which is a true drawing of
    // what is known and a poor one of a family. Saying so beats leaving the
    // reader to wonder why the tree is flat.
    final unplaced =
        path.steps.isNotEmpty &&
        path.steps.every((step) => step.direction == StepDirection.unknown);

    final layout = layoutRelationshipPath(path, widthOf: _measurer(context));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ViewSwitch(view: view, onView: onView),
              const SizedBox(height: 12),
              RelationshipSummary(
                description: path.description,
                steps: path.steps.length,
              ),
              if (ways > 1) ...[
                const SizedBox(height: 8),
                _WayPicker(ways: ways, way: way, onWay: onWay),
              ],
              if (unplaced) ...[
                const SizedBox(height: 8),
                Text(
                  text.relationshipTreeUnplaced,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
        Expanded(
          child: ChartCanvas(
            // Arabic reads the other way, and so does its chart.
            layout: mirrored ? layout.mirrored() : layout,
            records: records,
            onTapPerson: (person) => onOpenPerson(person.xref),
          ),
        ),
      ],
    );
  }

  /// A box wide enough for the name in it.
  ///
  /// A path is a handful of people rather than a generation of them, so there
  /// is room to show every name in full — and a relationship whose boxes read
  /// `عبد الله ال…` answers a different question from the one asked.
  BoxWidth _measurer(BuildContext context) {
    const metrics = ChartMetrics();
    final style = Theme.of(context).textTheme.labelMedium;
    final direction = Directionality.of(context);

    return (person) {
      final painter = TextPainter(
        text: TextSpan(text: person.name, style: style),
        textDirection: direction,
        maxLines: 1,
      )..layout();

      return (painter.width + 48 + 24).clamp(
        metrics.boxWidth,
        metrics.boxWidth * 2.2,
      );
    };
  }
}

/// Which of the two drawings the reader is looking at.
class _ViewSwitch extends StatelessWidget {
  const _ViewSwitch({required this.view, required this.onView});

  final RelationshipView view;

  /// Null while there is nothing to draw, which shows the switch disabled
  /// rather than hiding it.
  final ValueChanged<RelationshipView>? onView;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final change = onView;

    return SegmentedButton<RelationshipView>(
      showSelectedIcon: false,
      segments: [
        ButtonSegment(
          value: RelationshipView.path,
          icon: const Icon(Icons.timeline, size: 18),
          label: Text(text.relationshipViewPath),
          enabled: change != null,
        ),
        ButtonSegment(
          value: RelationshipView.tree,
          icon: const Icon(Icons.account_tree_outlined, size: 18),
          label: Text(text.relationshipViewTree),
          enabled: change != null,
        ),
      ],
      selected: {view},
      onSelectionChanged: change == null
          ? null
          : (chosen) => change(chosen.first),
    );
  }
}

/// Which of several ways the tree is drawing.
class _WayPicker extends StatelessWidget {
  const _WayPicker({
    required this.ways,
    required this.way,
    required this.onWay,
  });

  final int ways;
  final int way;
  final ValueChanged<int> onWay;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          tooltip: text.relationshipOtherWays,
          onPressed: way == 0 ? null : () => onWay(way - 1),
        ),
        Text(
          text.relationshipWayOf(way + 1, ways),
          style: Theme.of(context).textTheme.labelLarge,
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          tooltip: text.relationshipOtherWays,
          onPressed: way == ways - 1 ? null : () => onWay(way + 1),
        ),
      ],
    );
  }
}

/// The heading above one of the other ways, and the button that draws it.
class _OtherWayHeader extends StatelessWidget {
  const _OtherWayHeader({required this.description, required this.onDrawTree});

  final String description;
  final VoidCallback onDrawTree;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = AppText.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              description,
              textDirection: directionOf(description),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.account_tree_outlined),
            tooltip: text.relationshipDrawTree,
            onPressed: onDrawTree,
          ),
        ],
      ),
    );
  }
}

/// The person the subject is being compared with, and a way to change them.
class _Comparing extends StatelessWidget {
  const _Comparing({
    required this.person,
    required this.records,
    required this.onChooseAgain,
  });

  final PersonRef person;
  final RecordsTransport records;
  final VoidCallback onChooseAgain;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);

    return PersonTile(
      person: person,
      records: records,
      relationship: text.relationshipWith,
      trailing: IconButton(
        icon: const Icon(Icons.search),
        tooltip: text.relationshipChoose,
        onPressed: onChooseAgain,
      ),
      onOpen: onChooseAgain,
    );
  }
}

/// The ways of asking the question.
///
/// A side with no path is shown disabled rather than hidden: "there is no
/// link on your mother's side" is an answer, and a missing button is not.
class _Ways extends StatelessWidget {
  const _Ways({
    required this.routes,
    required this.side,
    required this.onSide,
    required this.bloodOnly,
    required this.onBloodOnly,
  });

  final RelationshipRoutes routes;
  final RelationshipSide side;
  final ValueChanged<RelationshipSide> onSide;
  final bool bloodOnly;
  final ValueChanged<bool> onBloodOnly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = AppText.of(context);

    String label(RelationshipSide which) => switch (which) {
      RelationshipSide.closest => text.relationshipClosest,
      RelationshipSide.fatherSide => text.relationshipFatherSide,
      RelationshipSide.motherSide => text.relationshipMotherSide,
      RelationshipSide.throughSpouse => text.relationshipThroughSpouse,
    };

    IconData icon(RelationshipSide which) => switch (which) {
      RelationshipSide.closest => Icons.timeline,
      RelationshipSide.fatherSide => Icons.male,
      RelationshipSide.motherSide => Icons.female,
      RelationshipSide.throughSpouse => Icons.favorite_outline,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text.relationshipHow,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final which in RelationshipSide.values)
              ChoiceChip(
                avatar: Icon(icon(which), size: 17),
                label: Text(label(which)),
                selected: which == side,
                onSelected: routes.offers(which) ? (_) => onSide(which) : null,
              ),
          ],
        ),
        const SizedBox(height: 4),
        // The one thing the server itself can be asked differently, and the
        // only way a link through a marriage is ever found.
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: bloodOnly,
          onChanged: onBloodOnly,
          title: Text(
            bloodOnly
                ? text.relationshipBloodOnlyToggle
                : text.relationshipAnyLink,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}

/// Finds the other person.
///
/// The same search the tree screen uses, without its paging: somebody looking
/// for one person to compare against is naming them, not browsing.
class _PersonPicker extends StatefulWidget {
  const _PersonPicker({
    required this.session,
    required this.records,
    required this.tree,
    required this.prompt,
    required this.onPicked,
  });

  final SessionManager session;
  final RecordsTransport records;
  final String tree;
  final String prompt;
  final void Function(PersonRef person) onPicked;

  @override
  State<_PersonPicker> createState() => _PersonPickerState();
}

class _PersonPickerState extends State<_PersonPicker> {
  Timer? _debounce;
  List<PersonRef> _results = const [];
  bool _searching = false;
  int _generation = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(query));
  }

  Future<void> _search(String query) async {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() => _results = const []);
      return;
    }

    final generation = ++_generation;
    setState(() => _searching = true);
    try {
      final page = await widget.session.withSession(
        () => widget.records.search(widget.tree, query),
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _results = page.people;
        _searching = false;
      });
    } on WebtreesError {
      if (!mounted || generation != _generation) return;
      setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.prompt,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              TextField(
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
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
            itemCount: _results.length,
            itemBuilder: (context, index) {
              final person = _results[index];
              return PersonTile(
                person: person,
                records: widget.records,
                onOpen: () => widget.onPicked(person),
              );
            },
          ),
        ),
      ],
    );
  }
}
