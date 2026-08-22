import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/domain/charts.dart';
import 'package:webtrees_mobile/features/charts/timeline_layout.dart';

TimelineChart chartOf(List<double> events) => TimelineChart(
  ticks: const [
    TimelineTick(year: 1900, position: 0),
    TimelineTick(year: 1905, position: 50),
    TimelineTick(year: 1910, position: 100),
  ],
  events: [
    for (final position in events)
      TimelineEvent(label: 'event at $position', position: position),
  ],
);

void main() {
  const metrics = TimelineMetrics();

  group('a timeline', () {
    test('keeps the spacing the site worked out', () {
      // Two events ten years apart must not be drawn as far apart as two
      // events fifty years apart. The proportions are the whole point.
      final layout = layoutTimeline(chartOf([0, 50, 100]));

      expect(layout.events.first.at, 0);
      expect(layout.events[1].at, metrics.height / 2);
      expect(layout.events.last.at, metrics.height);
    });

    test('labels the scale without printing every year', () {
      final layout = layoutTimeline(chartOf([50]), tickEvery: 10);

      // 1905 falls between the decades and is not drawn.
      expect(layout.ticks.map((tick) => tick.year), [1900, 1910]);
    });

    test('nudges a crowded card down and remembers where it belongs', () {
      // Three events within a few pixels of each other would draw as one
      // card with two hidden behind it.
      final layout = layoutTimeline(chartOf([0, 1, 2]));

      final tops = layout.events.map((placed) => placed.cardTop).toList();
      expect(tops[1] - tops[0], greaterThanOrEqualTo(metrics.cardHeight));
      expect(tops[2] - tops[1], greaterThanOrEqualTo(metrics.cardHeight));
      // The dots stay where the events actually fall, so a line can point
      // back at the moment from the card that had to move.
      expect(layout.events[1].at, lessThan(layout.events[1].cardTop));
    });

    test('grows tall enough for a card pushed past the end', () {
      final layout = layoutTimeline(chartOf([98, 99, 100]));
      expect(layout.height, greaterThan(metrics.height));
    });

    test('an event and a tick at the same point land together', () {
      final layout = layoutTimeline(chartOf([100]));
      expect(layout.events.single.at, layout.ticks.last.at);
    });
  });
}
