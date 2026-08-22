/// Keeping Latin runs readable inside Arabic text.
///
/// A lifespan like `1875–1940` carries no strong direction of its own: every
/// character in it is a digit or a dash. Dropped into an Arabic paragraph the
/// bidirectional algorithm lays it out right to left, and the person appears
/// to have died before they were born. The fix is to isolate the run, which is
/// what webtrees itself does in the markup it sends.
library;

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
