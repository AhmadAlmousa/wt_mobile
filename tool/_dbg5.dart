import 'dart:convert';
import 'dart:io';
import 'package:html/parser.dart' as html;

List<String> argumentsAt(String script, int start) {
  final arguments = <String>[];
  final buffer = StringBuffer();
  var depth = 0;
  var quoted = false;
  var escaped = false;

  for (var index = start; index < script.length; index++) {
    final character = script[index];
    if (escaped) { buffer.write(character); escaped = false; continue; }
    if (quoted) {
      buffer.write(character);
      if (character == r'\') escaped = true;
      if (character == '"') quoted = false;
      continue;
    }
    switch (character) {
      case '"': quoted = true; buffer.write(character);
      case '[' || '{': depth++; buffer.write(character);
      case ']' || '}': depth--; buffer.write(character);
      case ',' when depth == 0:
        arguments.add(buffer.toString().trim());
        buffer.clear();
      case ')' when depth == 0:
        final last = buffer.toString().trim();
        if (last.isNotEmpty) arguments.add(last);
        return arguments;
      default: buffer.write(character);
    }
  }
  return arguments;
}

void main(List<String> args) {
  final doc = html.parseFragment(File(args[0]).readAsStringSync());
  final script = doc.querySelectorAll('script').first.text;
  final m = RegExp(r'statistics\.draw(\w+?)Chart\s*\(').firstMatch(script)!;
  final parsed = argumentsAt(script, m.end);
  stdout.writeln('\nargs: ${parsed.length}');
  for (final a in parsed) {
    stdout.writeln('  [${a.length}] ${a.substring(0, a.length.clamp(0, 70))}');
  }
  if (parsed.length > 1) {
    try {
      final data = jsonDecode(parsed[1]);
      stdout.writeln('decoded: $data');
    } catch (e) {
      stdout.writeln('decode failed: $e');
    }
  }
}
