/// Recovering GEDCOM tags from a page webtrees already translated.
///
/// Every label webtrees prints beside a fact — `Death`, `وفاة`, `Divorce` —
/// is translated by the server before it reaches the app. An interface that
/// switched on those words would work in English and quietly do nothing in
/// the language this app was built for.
///
/// Its own chart boxes give the answer away. `Fact::summary()` renders each
/// fact as `<div class="fact_DEAT"><span class="label">…</span>: …</div>` —
/// the class carries the GEDCOM tag, the span carries this site's translation
/// of it — and webtrees puts a run of those inside every `chart-box`: the
/// person's birth and death in `.wt-chart-box-facts`, and *everything*, their
/// spouse families included, in the hidden `.wt-chart-box-zoom-dropdown`
/// beside it.
///
/// The tag in that class is **bare**: `Fact::summary()` builds the class from
/// the fact's own `$tag` property — the word off the GEDCOM line — and not
/// from `Fact::tag()`, which qualifies it with the record type. So a family's
/// divorce is `fact_DIV` and not `fact_FAM:DIV`. Nothing is lost by that: a
/// death is only ever an individual's and a divorce only ever a family's.
///
/// So a page that shows any person at all teaches the app what this site
/// calls a death and what it calls a divorce, and that dictionary then names
/// the fact rows everywhere else on the same page — the relatives tab's
/// per-family marriage rows, the personal facts table, a descendants chart's
/// captions — without a word of English in the parser.
library;

import 'package:html/dom.dart';
import 'package:meta/meta.dart';

import 'dom.dart';

/// The GEDCOM tags webtrees treats as the end of a life.
///
/// `Gedcom::DEATH_EVENTS` upstream. A burial without a death record still
/// means the person is not living.
const Set<String> deathTags = {'DEAT', 'BURI', 'CREM'};

/// The GEDCOM tags webtrees treats as the end of a relationship.
///
/// `Gedcom::DIVORCE_EVENTS` upstream.
const Set<String> divorceTags = {'DIV', 'ANUL', '_SEPR'};

/// The GEDCOM tags webtrees treats as the start of one.
///
/// `Gedcom::MARRIAGE_EVENTS` upstream.
const Set<String> marriageTags = {'MARR', '_NMR'};

/// What this site calls each kind of fact, learned from its own markup.
///
/// Immutable and cheap to build: one pass over the fact blocks of a fragment
/// the app has already fetched and parsed. An empty index is an ordinary
/// outcome — a theme that renders no fact blocks, a page with no chart boxes
/// — and means "this page said nothing", never "there is no death here". Every
/// reader has to degrade rather than guess.
@immutable
final class FactTagIndex {
  FactTagIndex(Map<String, String> tagsByLabel)
    : _tagsByLabel = Map.unmodifiable(tagsByLabel);

  /// An index that knows nothing, for a page that offered no fact blocks.
  static final FactTagIndex empty = FactTagIndex(const {});

  /// Lower-cased label to the tag it stood for, e.g. `وفاة` → `DEAT`.
  ///
  /// Lower-cased because a label may be rendered with different capitals in
  /// different places — a table header and a chart box — while Arabic, which
  /// has no letter case, is unaffected either way.
  final Map<String, String> _tagsByLabel;

  bool get isEmpty => _tagsByLabel.isEmpty;
  bool get isNotEmpty => _tagsByLabel.isNotEmpty;

  /// Reads every `fact_RECORD:TAG` block inside [root].
  ///
  /// Later blocks do not overwrite earlier ones: webtrees renders the same
  /// label for the same tag throughout a page, and where two tags somehow
  /// share a label the first is as good an answer as the second.
  factory FactTagIndex.from(Node root) {
    final tags = <String, String>{};

    for (final element in _elementsIn(root)) {
      final tag = tagOf(element);
      if (tag == null) continue;

      final label = textOf(element.querySelector('.label'));
      if (label == null) continue;

      tags.putIfAbsent(_key(label), () => tag);
    }
    return FactTagIndex(tags);
  }

  /// The tag [label] stands for on this site, or null when this page never
  /// named one.
  String? tagFor(String? label) =>
      label == null ? null : _tagsByLabel[_key(label)];

  /// Whether [label] names a fact that ends a life.
  bool isDeath(String? label) => _isOneOf(tagFor(label), deathTags);

  /// Whether [label] names a fact that ends a relationship.
  bool isDivorce(String? label) => _isOneOf(tagFor(label), divorceTags);

  /// Whether any divorce label this site uses appears inside [caption].
  ///
  /// For the places webtrees writes several labels into one run of text: a
  /// descendants chart announces a family as "Marriage 1925 — Divorce 1931 —
  /// 2 children", with no markup separating the parts. Since the labels come
  /// from the same `Fact::label()` that filled this index, a containment test
  /// is exact rather than a guess at wording.
  bool mentionsDivorce(String? caption) {
    if (caption == null || _tagsByLabel.isEmpty) return false;
    final haystack = _key(caption);

    for (final entry in _tagsByLabel.entries) {
      if (_isOneOf(entry.value, divorceTags) &&
          entry.key.isNotEmpty &&
          haystack.contains(entry.key)) {
        return true;
      }
    }
    return false;
  }

  /// The GEDCOM tag a `fact_DEAT` class names, or null when the element
  /// carries no such class.
  ///
  /// A qualifying prefix is accepted and dropped. Stock webtrees does not
  /// write one — see the note above — but a theme or a custom module that
  /// built the class from `Fact::tag()` instead would, and reading `DEAT` out
  /// of `fact_INDI:DEAT` costs one line.
  static String? tagOf(Element element) {
    for (final name in element.classes) {
      final match = _factClass.firstMatch(name);
      if (match != null) return match.group(1);
    }
    return null;
  }

  /// The bare tag of a possibly qualified one: `INDI:DEAT` → `DEAT`.
  static String? bareTagOf(String? tag) {
    if (tag == null) return null;
    final colon = tag.indexOf(':');
    return colon < 0 ? tag : tag.substring(colon + 1);
  }

  /// Whether [tag] names one of [wanted], which are bare tags.
  static bool _isOneOf(String? tag, Set<String> wanted) {
    final bare = bareTagOf(tag);
    return bare != null && wanted.contains(bare);
  }

  /// Whitespace collapsed and case folded, so the same label found in two
  /// places matches itself.
  static String _key(String label) =>
      (cleanText(label) ?? '').toLowerCase();

  /// Every element under [root], whichever kind of node it is.
  ///
  /// A fragment and a document both hold elements but neither is one, so
  /// `querySelectorAll` has to be reached through the right type.
  static Iterable<Element> _elementsIn(Node root) => switch (root) {
    Element() => root.querySelectorAll('*'),
    Document() => root.querySelectorAll('*'),
    DocumentFragment() => root.querySelectorAll('*'),
    _ => const <Element>[],
  };

  /// `fact_DEAT`, `fact__SEPR`, and the qualified `fact_FAM:DIV` a theme
  /// might write. The tag may begin with an underscore, as webtrees' own
  /// extensions do.
  static final RegExp _factClass = RegExp(
    r'^fact_(?:[A-Z]+:)?([_A-Z][_A-Z0-9]*)$',
  );
}
