import 'dart:io';
import 'package:html/parser.dart' as html;

void main(List<String> args) {
  final doc = html.parseFragment(File(args[0]).readAsStringSync());
  final scripts = doc.querySelectorAll('script');
  stdout.writeln('scripts: ${scripts.length}');
  for (final s in scripts.take(2)) {
    final text = s.text;
    stdout.writeln('len=${text.length} draw=${text.contains('statistics.draw')}');
    final i = text.indexOf('statistics.draw');
    if (i >= 0) stdout.writeln(text.substring(i, i + 120).replaceAll('\n', ' '));
  }
  stdout.writeln('h4: ${doc.querySelectorAll('h4').length}');
}
