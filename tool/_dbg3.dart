import 'dart:io';
import 'package:html/parser.dart' as html;
import 'package:webtrees_mobile/data/stock/statistics_parser.dart';

void main(List<String> args) {
  final doc = html.parseFragment(File(args[0]).readAsStringSync());
  final all = doc.querySelectorAll('h4, h5, script');
  stdout.writeln('\nelements: ${all.map((e) => e.localName).toList()}');
  final sections = const StatisticsParser().parseSections(
    File(args[0]).readAsStringSync(),
  );
  stdout.writeln('datasets: ${sections.map((s) => s.datasets.length).toList()}');
}
