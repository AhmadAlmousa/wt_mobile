/// Small helpers over `package:html`, shared by the stock parsers.
///
/// The protocol spike matched markup with regular expressions, which depend on
/// attribute order and quote style. Record pages are far richer than the
/// handful of meta tags that justified it, so everything here selects against
/// the parsed DOM instead.
library;

import 'package:html/dom.dart';

/// The element's visible text, whitespace collapsed, or null when empty.
///
/// webtrees indents its templates generously, so raw `text` arrives full of
/// newlines and runs of spaces that would otherwise reach the interface.
String? textOf(Element? element) {
  if (element == null) return null;
  return cleanText(element.text);
}

/// Collapses whitespace and trims, returning null for an empty result.
String? cleanText(String? raw) {
  if (raw == null) return null;
  final text = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  return text.isEmpty ? null : text;
}

/// The text of [element] with every [strip] descendant removed first.
///
/// Several webtrees fields interleave the value with annotations — a date sits
/// in the same box as the ages it implies — and the annotations are only
/// separable before the text is flattened.
String? textWithout(Element? element, List<String> strip) {
  if (element == null) return null;
  final copy = element.clone(true);
  for (final selector in strip) {
    for (final unwanted in copy.querySelectorAll(selector)) {
      unwanted.remove();
    }
  }
  return cleanText(copy.text);
}

/// The record identifier inside a webtrees URL, for [type] such as
/// `individual` or `family`.
///
/// Handles both URL styles: `/tree/main/individual/X42/slug` and
/// `index.php?route=%2Ftree%2Fmain%2Findividual%2FX42`.
String? xrefIn(String? url, String type) {
  if (url == null) return null;
  final decoded = Uri.decodeFull(url);
  return RegExp('/$type/([^/?&#]+)').firstMatch(decoded)?.group(1);
}

/// The first link inside [element] that points at a record of [type].
///
/// webtrees links to a record by a URL the app cannot reliably match with a
/// CSS attribute selector — the two URL styles put the xref in a path segment
/// or inside an encoded query — so the match is made on the parsed href.
Element? recordLink(Element? element, String type) {
  if (element == null) return null;
  for (final link in element.querySelectorAll('a[href]')) {
    if (xrefIn(link.attributes['href'], type) != null) return link;
  }
  return null;
}

/// The text of [element] with [unwanted] descendants removed first.
///
/// Like [textWithout], but for elements already found rather than selectors:
/// the record links this file matches are recognised by their href, which no
/// selector can express.
String? textExcluding(Element element, Iterable<Element> unwanted) {
  final drop = unwanted.map((e) => e.outerHtml).toSet();
  final copy = element.clone(true);
  for (final candidate in copy.querySelectorAll('*')) {
    if (drop.contains(candidate.outerHtml)) candidate.remove();
  }
  return cleanText(copy.text);
}
