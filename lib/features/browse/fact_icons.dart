/// An icon for each kind of event a record holds.
///
/// Keyed on the GEDCOM tag rather than on the label webtrees printed, which
/// is already translated — an icon table keyed on the word "Death" would go
/// blank the moment the reader switched to Arabic. The tags come from
/// [FactTagIndex], which learns them from the site's own markup.
///
/// The set is deliberately small and secular. This app's first real tree is a
/// Muslim family's, and the headstone every genealogy program reaches for
/// would be the wrong mark on their page; an hourglass says "a life ended"
/// without saying whose faith ended it.
library;

import 'package:flutter/material.dart';

import '../../data/stock/fact_tags.dart';

/// The icon standing for the fact [tag] names.
///
/// [tag] is bare (`DEAT`), which is what webtrees writes, or qualified
/// (`INDI:DEAT`), which a theme might. A tag this table does not know, and a
/// fact whose tag was never discovered, both get the neutral default — which
/// is why that default has to read as "an event" rather than as anything in
/// particular.
IconData iconForFact(String? tag) {
  final bare = FactTagIndex.bareTagOf(tag);
  return _icons[bare] ?? Icons.event_outlined;
}

const Map<String, IconData> _icons = {
  // A life, in the order it is lived.
  'BIRT': Icons.cake_outlined,
  'CHR': Icons.cake_outlined,
  'BAPM': Icons.water_drop_outlined,
  'ADOP': Icons.volunteer_activism_outlined,
  'EDUC': Icons.school_outlined,
  'GRAD': Icons.school_outlined,
  'OCCU': Icons.work_outline,
  'RETI': Icons.beach_access_outlined,
  'RESI': Icons.home_outlined,
  'CENS': Icons.how_to_reg_outlined,
  'IMMI': Icons.flight_land_outlined,
  'EMIG': Icons.flight_takeoff_outlined,
  'NATU': Icons.flag_outlined,
  'RELI': Icons.auto_awesome_outlined,
  'NATI': Icons.public_outlined,
  'TITL': Icons.workspace_premium_outlined,
  'DEAT': Icons.hourglass_bottom_outlined,
  'BURI': Icons.landscape_outlined,
  'CREM': Icons.landscape_outlined,
  'PROB': Icons.gavel_outlined,
  'WILL': Icons.description_outlined,

  // A marriage, and how it ended.
  'MARR': Icons.favorite_outline,
  'ENGA': Icons.diamond_outlined,
  'MARB': Icons.article_outlined,
  '_NMR': Icons.link_outlined,
  'DIV': Icons.heart_broken_outlined,
  'DIVF': Icons.heart_broken_outlined,
  'ANUL': Icons.heart_broken_outlined,
  '_SEPR': Icons.heart_broken_outlined,

  // Things recorded about a person rather than done by them.
  'NOTE': Icons.sticky_note_2_outlined,
  'SOUR': Icons.menu_book_outlined,
  'OBJE': Icons.photo_outlined,
  'EVEN': Icons.event_note_outlined,
  'FACT': Icons.info_outline,
  'NAME': Icons.badge_outlined,
  'SEX': Icons.wc_outlined,
};
