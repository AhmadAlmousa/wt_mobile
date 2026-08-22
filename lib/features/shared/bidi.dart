/// Keeping text readable when its script and the interface's disagree.
///
/// A lifespan like `1875–1940` carries no strong direction of its own: every
/// character in it is a digit or a dash. Dropped into an Arabic paragraph the
/// bidirectional algorithm lays it out right to left, and the person appears
/// to have died before they were born. The fix is to isolate the run, which is
/// what webtrees itself does in the markup it sends.
library;

import 'dart:ui' show TextDirection;

/// U+2066: lays the run out left to right regardless of what is in it.
const String _leftToRightIsolate = '\u2066';

/// U+2068: lays the run out according to its own first strong character.
const String _firstStrongIsolate = '\u2068';

/// U+2069: ends an isolate.
const String _popDirectionalIsolate = '\u2069';

/// [text] laid out left to right, whatever surrounds it.
///
/// For runs that are Latin or numeric by nature — a lifespan, a version, a
/// record id — and would otherwise be reordered by the paragraph around them.
String ltrRun(String? text) => text == null || text.isEmpty
    ? ''
    : '$_leftToRightIsolate$text$_popDirectionalIsolate';

/// [text] laid out according to its own script, whatever surrounds it.
///
/// For runs whose direction cannot be known in advance: a second recorded
/// name may be Arabic beside an Arabic one or romanized beside it, and only
/// the text itself can say.
String isolatedRun(String? text) => text == null || text.isEmpty
    ? ''
    : '$_firstStrongIsolate$text$_popDirectionalIsolate';

/// The direction [text] should be laid out in, judged by its own script.
///
/// A tree records names, places and notes in the family's language, whichever
/// language the reader has chosen for the app — so an Arabic note may have to
/// be shown on an English screen, and it belongs on the right of its card with
/// its full stop at the left end. This is what webtrees does with `dir="auto"`
/// on the same content, and what the bidirectional algorithm calls a
/// paragraph's direction: the first *strong* character decides.
///
/// Returns null when nothing in the text is strong either way — a bare year, a
/// record id — leaving the surrounding direction to decide, which is what
/// [ltrRun] and [isolatedRun] handle within a line.
TextDirection? directionOf(String? text) {
  if (text == null) return null;

  for (final rune in text.runes) {
    if (_isRightToLeft(rune)) return TextDirection.rtl;
    if (_isLeftToRightLetter(rune)) return TextDirection.ltr;
  }
  return null;
}

/// The blocks Unicode gives a right-to-left direction: Hebrew, Arabic,
/// Syriac, Thaana, NKo, Samaritan, and the Arabic presentation forms.
bool _isRightToLeft(int rune) =>
    (rune >= 0x0590 && rune <= 0x08FF) ||
    (rune >= 0xFB1D && rune <= 0xFDFF) ||
    (rune >= 0xFE70 && rune <= 0xFEFF) ||
    (rune >= 0x10800 && rune <= 0x10CFF) ||
    (rune >= 0x1E800 && rune <= 0x1EFFF);

/// Any other letter, which by definition reads left to right here. Digits and
/// punctuation are deliberately not strong: `1901` says nothing about the
/// direction of the sentence it sits in.
bool _isLeftToRightLetter(int rune) =>
    _letter.hasMatch(String.fromCharCode(rune));

final RegExp _letter = RegExp(r'\p{L}', unicode: true);
