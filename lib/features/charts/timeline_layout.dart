/// Placing a timeline down a phone screen.
///
/// The site states where each event sits and where each year sits, both as
/// positions in its own drawing. Those positions are kept in proportion here
/// and nothing is converted to a date: the label already carries the date, in
/// the calendars this tree converts to.
library;

import 'package:meta/meta.dart';

import '../../domain/charts.dart';

/// How a timeline is spaced.
@immutable
final class TimelineMetrics {
  const TimelineMetrics({
    this.height = 900,
    this.cardHeight = 56,
    this.cardGap = 8,
  });

  /// How tall the whole scale is drawn, before any card has to be nudged.
  final double height;

  final double cardHeight;
  final double cardGap;
}

/// One event, at the point it happened and at the point its card is drawn.
@immutable
final class PlacedEvent {
  const PlacedEvent({
    required this.event,
    required this.at,
    required this.cardTop,
  });

  final TimelineEvent event;

  /// Where on the scale the event actually falls.
  final double at;

  /// Where its card ended up, which is lower when two events crowd.
  final double cardTop;
}

/// One year label on the scale.
@immutable
final class PlacedTick {
  const PlacedTick({required this.year, required this.at});

  final int year;
  final double at;
}

/// A timeline, placed.
@immutable
final class TimelineLayout {
  TimelineLayout({
    required List<PlacedTick> ticks,
    required List<PlacedEvent> events,
    required this.height,
  }) : ticks = List.unmodifiable(ticks),
       events = List.unmodifiable(events);

  final List<PlacedTick> ticks;
  final List<PlacedEvent> events;
  final double height;
}

/// Lays a timeline out down the screen.
///
/// Cards never overlap: where two events fall within a card of each other the
/// second is pushed down and a line still points back at the moment it
/// happened. A chart that let them collide would hide one of them, and a
/// chart that spaced them evenly would say they were evenly spaced in time.
TimelineLayout layoutTimeline(
  TimelineChart chart, {
  TimelineMetrics metrics = const TimelineMetrics(),

  /// One label every so many years, so a century of scale does not become a
  /// column of a hundred numbers.
  int tickEvery = 10,
}) {
  final (first, last) = chart.extent;
  final span = last - first;

  double at(double position) =>
      span == 0 ? 0 : (position - first) / span * metrics.height;

  final events = [...chart.events]
    ..sort((a, b) => a.position.compareTo(b.position));

  final placed = <PlacedEvent>[];
  var lowest = 0.0;
  for (final event in events) {
    final point = at(event.position);
    final top = point < lowest ? lowest : point;
    placed.add(PlacedEvent(event: event, at: point, cardTop: top));
    lowest = top + metrics.cardHeight + metrics.cardGap;
  }

  final ticks = [
    for (final tick in chart.ticks)
      if (tick.year % tickEvery == 0)
        PlacedTick(year: tick.year, at: at(tick.position)),
  ];

  return TimelineLayout(
    ticks: ticks,
    events: placed,
    // Long enough for the last card, which may have been pushed past the end
    // of the scale by the ones above it.
    height: [
      metrics.height,
      if (placed.isNotEmpty) placed.last.cardTop + metrics.cardHeight,
    ].reduce((a, b) => a > b ? a : b),
  );
}
