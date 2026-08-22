/// Dates as webtrees renders them, kept structured enough to choose a
/// calendar without ever re-formatting the date itself.
library;

import 'package:meta/meta.dart';

/// A calendar webtrees can render a date in.
///
/// Named from the GEDCOM escapes webtrees puts in its calendar links
/// (`@#DGREGORIAN@`, `@#DHIJRI@` …), which is the only machine-readable
/// statement of a rendered date's calendar on a stock site.
enum DateCalendar {
  gregorian,
  julian,
  hijri,
  jewish,
  french,
  jalali,
  roman,

  /// The markup did not say. Older or newer renderings drop the calendar
  /// links, and a preference then falls back to document order.
  unknown;

  /// Reads the `cal` parameter of a webtrees calendar URL.
  static DateCalendar fromGedcomEscape(String? escape) =>
      switch (escape?.toUpperCase().replaceAll(RegExp(r'[@#D\s]'), '')) {
        'GREGORIAN' => DateCalendar.gregorian,
        'JULIAN' => DateCalendar.julian,
        'HIJRI' => DateCalendar.hijri,
        'HEBREW' => DateCalendar.jewish,
        'FRENCHR' => DateCalendar.french,
        'JALALI' => DateCalendar.jalali,
        'ROMAN' => DateCalendar.roman,
        _ => DateCalendar.unknown,
      };
}

/// Which calendar the reader wants to see.
///
/// webtrees renders a date in the calendar the GEDCOM records it in, then
/// appends a conversion to whatever the *tree* is configured to convert to.
/// That is a tree preference no member can change, so the choice is made here,
/// over markup the server has already produced.
enum CalendarView {
  /// Both, exactly as webtrees rendered them.
  both,

  gregorian,

  hijri;

  /// The calendar this view asks for, or null when it asks for everything.
  DateCalendar? get calendar => switch (this) {
    CalendarView.both => null,
    CalendarView.gregorian => DateCalendar.gregorian,
    CalendarView.hijri => DateCalendar.hijri,
  };
}

/// One piece of a rendered date.
sealed class DatePiece {
  const DatePiece();
}

/// Words webtrees wrapped a date in — “about”, “between”, “and”, a time.
///
/// Kept because dropping them would turn “between 1900 and 1910” into two bare
/// years, and the qualifier is part of what the record actually says.
@immutable
final class DateWords extends DatePiece {
  const DateWords(this.text);

  final String text;
}

/// A date, with any conversions webtrees rendered beside it.
@immutable
final class DateValue extends DatePiece {
  DateValue({
    required this.text,
    this.calendar = DateCalendar.unknown,
    List<DateValue> conversions = const [],
  }) : conversions = List.unmodifiable(conversions);

  /// The date exactly as webtrees wrote it, in its own numerals.
  final String text;

  final DateCalendar calendar;

  /// The same moment in the calendars the tree converts to.
  final List<DateValue> conversions;

  /// This value in [wanted], or null when neither it nor its conversions are
  /// in that calendar.
  DateValue? inCalendar(DateCalendar wanted) {
    if (calendar == wanted) return this;
    for (final conversion in conversions) {
      if (conversion.calendar == wanted) return conversion;
    }
    return null;
  }
}

/// A date as webtrees rendered it, plus enough structure to show one calendar.
///
/// [text] is authoritative: webtrees has already applied the tree's calendar,
/// the reader's language and its own numerals, and re-formatting would lose
/// the qualifiers and the conversion. The pieces exist only to *drop* parts of
/// it, never to rebuild a date from components.
@immutable
final class RenderedDate {
  RenderedDate({required this.text, List<DatePiece> pieces = const []})
    : pieces = List.unmodifiable(pieces);

  final String text;

  /// The date broken into words and values, in document order. Empty when the
  /// rendering carried no structure to read, in which case only [text] can be
  /// shown.
  final List<DatePiece> pieces;

  /// The date as [view] asks for it, falling back to the whole rendering
  /// whenever the wanted calendar is not among the ones on offer.
  String display(CalendarView view) {
    final wanted = view.calendar;
    if (wanted == null || pieces.isEmpty) return text;

    final parts = <String>[];
    var found = false;

    for (final piece in pieces) {
      switch (piece) {
        case DateWords(:final text):
          parts.add(text);
        case final DateValue value:
          final chosen = value.inCalendar(wanted);
          if (chosen != null) found = true;
          // A value with no version in the wanted calendar still has to be
          // shown: hiding it would silently delete a date from the record.
          parts.add((chosen ?? value).text);
      }
    }

    // Nothing was in that calendar at all, so the request was meaningless
    // here — show what the server sent rather than a rearranged copy of it.
    if (!found) return text;
    return parts.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  @override
  String toString() => text;
}
