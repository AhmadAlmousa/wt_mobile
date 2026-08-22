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

  return PersonRef(
    xref: xref,
    name: textOf(nameBox) ?? textOf(box.querySelector('a[href]')) ?? xref,
    alternateName: textOf(box.querySelector('.wt-chart-box-name-alt')),
    lifespan: textOf(box.querySelector('.wt-chart-box-lifespan')),
    sex: sexFromChartBox(box),
    thumbnailUrl: box
        .querySelector('.wt-chart-box-thumbnail img')
        ?.attributes['src'],
  );
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
