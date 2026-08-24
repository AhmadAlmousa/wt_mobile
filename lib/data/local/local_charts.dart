/// Charts drawn from this device's copy, with nothing to ask.
///
/// Phase 10d, and `sync_eval.md` §4 predicted its shape exactly: *"the shapes
/// are walks over the stored family links. The app already owns every layout;
/// only the shape was ever fetched."* That is the whole of this file — the
/// screens are untouched, because a chart has always been a `ChartData` and
/// where one came from was never their business.
///
/// **What makes the walk correct is what is missing from the store.** A record
/// the reader may not see was never synced (`sync_eval.md` §6: *a hidden
/// record is absent, not empty*), so the walk cannot reach it. Privacy pruning
/// therefore happens by construction rather than by a rule this file has to
/// remember to apply — the same property the server-side chart has, arrived at
/// from the other direction.
///
/// **What is honestly poorer than the server's.** webtrees writes a caption
/// above each family — *"Marriage 1925 — 2 children"* — built from
/// `Fact::label()` in the site's own language. The sync does not carry it, so
/// a locally drawn chart has no captions and `endedInDivorce` is always false,
/// which the model already documents as *"never said"* rather than "did not
/// happen". Everything a chart actually draws — the people, the generations,
/// the shape — is exact.
library;

import '../../core/errors.dart';
import '../../domain/charts.dart';
import '../../domain/records.dart';
import '../../domain/statistics.dart';
import '../transport.dart';
import 'local_records.dart';
import 'store.dart';

/// A handle naming a chart this device can draw for itself.
///
/// Handles are opaque to every screen — the whole reason `charts_repository`
/// mints them — so a local one only has to be recognisable to the transport
/// that made it. `local:` is that.
String localChartHandle(ChartKind kind, String tree, String xref) =>
    'local:${kind.name}:$tree:$xref';

/// Whether [handle] addresses this device rather than a site.
bool isLocalChartHandle(String handle) => handle.startsWith('local:');

/// Draws ancestor, descendant and hourglass charts out of the store.
///
/// Defers everything else to [online], which offline is a transport that says
/// so: a relationship needs kinship wording that is one of the largest things
/// in webtrees, and statistics are the site's own arithmetic — both stay
/// online permanently, for the reasons in `sync_eval.md` §5.
final class LocalChartsTransport implements ChartsTransport {
  const LocalChartsTransport({
    required this.store,
    required this.tree,
    required this.online,
    this.maxGenerations = 10,
  });

  final LocalStore store;
  final String tree;
  final ChartsTransport online;

  /// A ceiling, not a preference. A tree with a cycle in it — which a GEDCOM
  /// can express and webtrees does not forbid — would otherwise walk forever.
  final int maxGenerations;

  @override
  Future<ChartData> chart(
    ChartKind kind,
    String handle, {
    required PersonRef subject,
    int? generations,
  }) async {
    if (!isLocalChartHandle(handle)) {
      return online.chart(
        kind,
        handle,
        subject: subject,
        generations: generations,
      );
    }

    final depth = generations ?? maxGenerations;
    final people = await _people();
    final families = await _families();

    return switch (kind) {
      // Every upward chart is the same walk. What separates a pedigree from a
      // fan is how the app draws it, which is the point `PROJECT.md` §5 makes
      // about taking the shape and nothing else.
      ChartKind.ancestors ||
      ChartKind.pedigree ||
      ChartKind.fan ||
      ChartKind.compact => ChartData(
        kind: kind,
        subject: subject,
        ancestors: _ancestorsOf(subject.xref, people, families, depth),
      ),
      ChartKind.descendants => ChartData(
        kind: kind,
        subject: subject,
        descendants: _descendantsOf(subject.xref, people, families, depth),
      ),
      ChartKind.hourglass => ChartData(
        kind: kind,
        subject: subject,
        ancestors: _ancestorsOf(subject.xref, people, families, depth),
        descendants: _descendantsOf(subject.xref, people, families, depth),
      ),
      _ => throw NotAvailableOffline('this chart'),
    };
  }

  @override
  Future<ChartData> hourglass({
    required String ancestorsHandle,
    required String descendantsHandle,
    required PersonRef subject,
    int? generations,
  }) async {
    if (!isLocalChartHandle(ancestorsHandle)) {
      return online.hourglass(
        ancestorsHandle: ancestorsHandle,
        descendantsHandle: descendantsHandle,
        subject: subject,
        generations: generations,
      );
    }

    final depth = generations ?? maxGenerations;
    final people = await _people();
    final families = await _families();

    return ChartData(
      kind: ChartKind.hourglass,
      subject: subject,
      ancestors: _ancestorsOf(subject.xref, people, families, depth),
      descendants: _descendantsOf(subject.xref, people, families, depth),
    );
  }

  /// Straight through, and this one is worth explaining because it looks
  /// local and is not.
  ///
  /// A timeline is events positioned against a scale, and every position the
  /// app draws is **the site's own measurement in the site's own layout** —
  /// `TimelineEvent.position` documents why: reading a year back out of a
  /// box's position is arithmetic on somebody else's drawing, and it comes
  /// out a year short. Rebuilding the scale here would mean inventing a
  /// different one, so a timeline would move depending on whether the reader
  /// had signal.
  ///
  /// And there is nothing to build it from. A stored fact carries its date as
  /// webtrees *rendered* it — six calendars, `about`, `between … and …` — with
  /// no year behind it, because parsing one back out would discard the
  /// calendar and lose the qualifier (`RenderedDate`). Only a person's own
  /// birth and death years are stated outright, which is a lifespan and not a
  /// life.
  ///
  /// So the honest answer offline is that this needs the site, which is what
  /// [online] says.
  @override
  Future<TimelineChart> timeline(String handle) => online.timeline(handle);

  /// Straight through, permanently. `sync_eval.md` §5: the path between two
  /// people is a walk this file could do, and the **words on it** come from a
  /// table of kinship rules per language that is one of the largest things in
  /// webtrees. A second port of it into Dart is not a trade worth making.
  @override
  Future<List<RelationshipPath>> relationship(
    String handle, {
    required String from,
    required String to,
    bool? bloodLinesOnly,
  }) => online.relationship(
    handle,
    from: from,
    to: to,
    bloodLinesOnly: bloodLinesOnly,
  );

  @override
  bool bloodLinesOnly(String handle) => online.bloodLinesOnly(handle);

  /// Straight through, on purpose. The app reads statistics from the site's
  /// *page* because the page publishes seventeen sections where the module
  /// answers four; a store computing its own would show the app's arithmetic
  /// where every other screen shows the site's.
  @override
  Future<TreeStatistics> statistics(String handle) => online.statistics(handle);

  // ------------------------------------------------------------- the walks

  Future<Map<String, PersonRef>> _people() async {
    final rows = await (store.select(
      store.storedPeople,
    )..where((row) => row.tree.equals(tree))).get();

    return {for (final row in rows) row.xref: LocalRecordsTransport.refOf(row)};
  }

  /// Every family this copy knows, as spouses and children.
  Future<Map<String, _Family>> _families() async {
    final rows = await (store.select(
      store.storedMemberships,
    )..where((row) => row.tree.equals(tree))).get();

    final families = <String, _Family>{};
    for (final row in rows) {
      final family = families.putIfAbsent(row.familyXref, _Family.new);
      // A family is stated by every member, so the same membership arrives
      // many times — sets rather than lists, and order restored by sorting
      // against nothing, because the wire does not carry a birth order.
      if (row.role == 'spouse') {
        family.spouses.add(row.personXref);
      } else {
        family.children.add(row.personXref);
      }
    }
    return families;
  }

  AncestorNode? _ancestorsOf(
    String xref,
    Map<String, PersonRef> people,
    Map<String, _Family> families,
    int depth, {
    int sosa = 1,
    Set<String>? seen,
  }) {
    final person = people[xref];
    if (person == null) return null;

    // A GEDCOM can express a cycle and webtrees does not forbid one, so the
    // walk carries its own path rather than trusting the data.
    final walked = {...?seen, xref};

    final birthFamily = depth <= 1
        ? null
        : families.entries
              .where((entry) => entry.value.children.contains(xref))
              .firstOrNull;

    final parents = <AncestorNode>[];
    if (birthFamily != null) {
      // Father first, mother second, as webtrees emits them — recovered from
      // the stored sex rather than from a position, which is the ambiguity
      // `PROJECT.md` §7 bug 50 came from.
      final spouses = birthFamily.value.spouses.toList()
        ..sort((a, b) => _sexRank(people[a]).compareTo(_sexRank(people[b])));

      for (final (index, parent) in spouses.indexed) {
        if (walked.contains(parent)) continue;
        final node = _ancestorsOf(
          parent,
          people,
          families,
          depth - 1,
          sosa: sosa * 2 + index,
          seen: walked,
        );
        if (node != null) parents.add(node);
      }
    }

    return AncestorNode(
      person: person,
      sosa: sosa,
      familyXref: birthFamily?.key,
      parents: parents,
    );
  }

  DescendantNode? _descendantsOf(
    String xref,
    Map<String, PersonRef> people,
    Map<String, _Family> families,
    int depth, {
    String number = '1',
    Set<String>? seen,
  }) {
    final person = people[xref];
    if (person == null) return null;

    final walked = {...?seen, xref};

    final own = depth <= 1
        ? <MapEntry<String, _Family>>[]
        : families.entries
              .where((entry) => entry.value.spouses.contains(xref))
              .toList();

    return DescendantNode(
      person: person,
      number: number,
      families: [
        for (final family in own)
          DescendantFamily(
            xref: family.key,
            spouse:
                people[family.value.spouses.firstWhere(
                  (each) => each != xref,
                  orElse: () => '',
                )],
            children: [
              for (final (index, child) in family.value.children.indexed)
                if (!walked.contains(child))
                  ?_descendantsOf(
                    child,
                    people,
                    families,
                    depth - 1,
                    number: '$number.${index + 1}',
                    seen: walked,
                  ),
            ],
          ),
      ],
    );
  }

  /// Fathers before mothers, and anybody unrecorded last.
  static int _sexRank(PersonRef? person) => switch (person?.sex) {
    Sex.male => 0,
    Sex.female => 1,
    _ => 2,
  };
}

final class _Family {
  final Set<String> spouses = {};
  final Set<String> children = {};
}
