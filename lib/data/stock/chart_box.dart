/// Reading webtrees' standard person card.
///
/// `chart-box` is the one piece of markup every part of webtrees agrees on: it
/// carries a person on the relatives tab, in a pedigree, in a fan chart and in
/// a relationship path. Everything that shows a person to the reader starts
/// here, which is why it is shared rather than copied per parser.
library;

import 'package:html/dom.dart';

import '../../domain/records.dart';
import 'dom.dart';
import 'fact_tags.dart';

/// The person one `chart-box` describes, or null when it names nobody.
///
/// A box with no `data-wt-chart-xref` is a placeholder webtrees draws where a
/// person is unknown — an empty slot in a pedigree, a family with one spouse
/// recorded.
PersonRef? personFromChartBox(Element box) {
  final xref = box.attributes['data-wt-chart-xref'];
  if (xref == null || xref.isEmpty) return null;

  final nameBox = box.querySelector(
    '.wt-chart-box-name:not(.wt-chart-box-name-alt)',
  );

  final lifespan = textOf(box.querySelector('.wt-chart-box-lifespan'));

  return PersonRef(
    xref: xref,
    name: textOf(nameBox) ?? textOf(box.querySelector('a[href]')) ?? xref,
    alternateName: textOf(box.querySelector('.wt-chart-box-name-alt')),
    lifespan: lifespan,
    sex: sexFromChartBox(box),
    isDeceased: deathRecordedIn(box, lifespan: lifespan),
    thumbnailUrl: box
        .querySelector('.wt-chart-box-thumbnail img')
        ?.attributes['src'],
  );
}

/// Whether this box says the person has died.
///
/// webtrees prints the person's own death event into `.wt-chart-box-facts`,
/// tagged in the class rather than only in the translated label — so the
/// question is answered structurally, in any language.
///
/// [lifespan] is the fallback, for a theme that renders no fact block at all.
/// `Individual::lifespan()` writes `birth–death` and leaves the second half
/// empty for somebody still living, filling it with an ellipsis when a death
/// is recorded without a date. So anything after the dash is a death; nothing
/// after it is silence, which is not the same as "alive" — see
/// [PersonRef.isDeceased].
bool deathRecordedIn(Element box, {String? lifespan}) {
  final facts = box.querySelector('.wt-chart-box-facts');
  var sawATaggedFact = false;

  for (final fact in facts?.querySelectorAll('*') ?? const <Element>[]) {
    final tag = FactTagIndex.bareTagOf(FactTagIndex.qualifiedTagOf(fact));
    if (tag == null) continue;
    if (deathTags.contains(tag)) return true;
    sawATaggedFact = true;
  }

  // A block that named some other fact and no death is a real statement that
  // there is none. A block that named nothing at all — an older theme, a
  // person whose facts this account may not see — has said nothing, so the
  // lifespan is asked instead.
  return sawATaggedFact ? false : _lifespanEndsInADeath(lifespan);
}

/// Whether a rendered lifespan carries a death year, an ellipsis included.
bool _lifespanEndsInADeath(String? lifespan) {
  if (lifespan == null) return false;

  // The separator is an en dash in every language: webtrees translates the
  // pair as a format string rather than as words, and no translation of it
  // replaces the dash.
  final dash = lifespan.lastIndexOf('–');
  if (dash < 0) return false;

  final after = cleanText(lifespan.substring(dash + 1));
  return after != null && after.isNotEmpty;
}

/// The sex webtrees encoded in the box's own class, `wt-chart-box-m`.
Sex sexFromChartBox(Element box) {
  for (final name in box.classes) {
    if (name.startsWith('wt-chart-box-') && name.length == 14) {
      return Sex.fromCssSuffix(name.substring(13));
    }
  }
  return Sex.unknown;
}

/// Every `chart-box` inside [element], in document order.
List<Element> chartBoxesIn(Element element) =>
    element.querySelectorAll('.wt-chart-box[data-wt-chart-xref]');
