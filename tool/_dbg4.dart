import 'dart:io';
import 'package:html/parser.dart' as html;

void main(List<String> args) {
  final doc = html.parseFragment(File(args[0]).readAsStringSync());
  final script = doc.querySelectorAll('script').first.text;
  final matches = RegExp(r'statistics\.draw(\w+?)Chart\s*\(').allMatches(script);
  stdout.writeln('\nmatches: ${matches.length} ${matches.map((m) => m.group(1)).toList()}');
  if (matches.isNotEmpty) {
    final start = matches.first.end;
    stdout.writeln('after: ${script.substring(start, start + 60).replaceAll('\n', '|')}');
  }
}
