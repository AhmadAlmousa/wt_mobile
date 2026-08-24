/// Reading a number a site wrote in its own numerals.
///
/// webtrees renders every number through the reader's locale, so an Arabic
/// site writes a year as `١٩٠١` and a Persian one as `۱۹۰۱`. The app almost
/// never needs the value — a rendered date is shown as it arrived, and a chart
/// computes its own Sosa numbers precisely so it never has to read the printed
/// ones — but a *filter* does: a range of years is arithmetic, and arithmetic
/// needs a number.
///
/// So this is deliberately narrow. It answers a year, or nothing.
library;

/// The value of a number written in any of the numeral systems webtrees can
/// render in, or null when [text] states none.
///
/// Every digit is taken, and everything else ignored: the year in `١٩٠١` and
/// the one in `about 1901` are both 1901, and `…` — which webtrees prints for
/// a year the tree does not record — is nothing. Two runs of digits answer the
/// first, because a *year* is one number and a second one is a qualifier the
/// value cannot carry anyway.
int? readNumber(String? text) {
  if (text == null) return null;

  var value = 0;
  var found = false;

  for (final rune in text.runes) {
    final digit = _digitValue(rune);
    if (digit == null) {
      // Stop at the first thing that is not a digit *after* one has been
      // seen, so `1901–1974` answers 1901 rather than 19011974.
      if (found) break;
      continue;
    }
    value = value * 10 + digit;
    found = true;
  }

  return found ? value : null;
}

/// What [rune] is worth as a decimal digit, or null when it is not one.
int? _digitValue(int rune) {
  for (final zero in _zeros) {
    final digit = rune - zero;
    if (digit >= 0 && digit <= 9) return digit;
  }
  return null;
}

/// The zero of every numeral system webtrees renders numbers in.
///
/// Taken from `fisharebest/localization`'s `Script*::numerals()`, which is
/// what `I18N::digits()` translates through — each of those is a run of ten
/// consecutive code points, which is what makes subtraction enough.
///
/// **Chinese numerals are deliberately absent.** `ScriptHani` writes
/// `〇一二三…`, which is not a contiguous run and not positional in the way
/// the rest are; a site rendering in it answers no year here, and a filter
/// with no year to filter on leaves every row alone. That is the right
/// failure: fewer answers, never a wrong one.
const List<int> _zeros = [
  0x0030, // Latin
  0x0660, // Arabic-Indic — this project's own tree
  0x06F0, // Extended Arabic-Indic: Persian, Urdu
  0x07C0, // NKo
  0x0966, // Devanagari
  0x09E6, // Bengali
  0x0A66, // Gurmukhi
  0x0AE6, // Gujarati
  0x0B66, // Oriya
  0x0BE6, // Tamil
  0x0C66, // Telugu
  0x0CE6, // Kannada
  0x0D66, // Malayalam
  0x0E50, // Thai
  0x0ED0, // Lao
  0x0F20, // Tibetan
  0x1040, // Myanmar
  0x17E0, // Khmer
  0x1810, // Mongolian
  0x1946, // Limbu
  0x19D0, // New Tai Lue
  0x1A80, // Tai Tham Hora
  0x1B50, // Balinese
  0x1BB0, // Sundanese
  0x1C40, // Lepcha
  0x1C50, // Ol Chiki
  0xA620, // Vai
  0xA8D0, // Saurashtra
  0xA900, // Kayah Li
  0xA9D0, // Javanese
  0xAA50, // Cham
  0xABF0, // Meetei Mayek
  0x11066, // Brahmi
  0x110F0, // Sora Sompeng
  0x11136, // Chakma
];
