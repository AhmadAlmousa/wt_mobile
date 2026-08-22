import 'dart:typed_data';

/// Keeps recently shown images in memory, for one account on one site.
///
/// Genealogy photos are private data. webtrees decides who may see a media
/// file per user — a signed thumbnail URL is not an access token — so bytes
/// fetched as one person must never be shown to the next. That makes the
/// lifetime the important part of this class: it belongs to a session, and
/// [clear] runs when the session ends or the account changes.
///
/// Deliberately memory-only. Writing family photographs to disk is a decision
/// for the person whose family they are, not a caching convenience.
final class MediaCache {
  MediaCache({this.capacity = 60});

  /// How many images to keep. Thumbnails are small; this bounds a long
  /// browsing session rather than trying to hold a whole tree.
  final int capacity;

  final Map<String, Uint8List> _entries = {};

  /// The cached bytes for [url], promoting it to most-recently-used.
  Uint8List? operator [](String url) {
    final bytes = _entries.remove(url);
    if (bytes != null) _entries[url] = bytes;
    return bytes;
  }

  void operator []=(String url, Uint8List bytes) {
    _entries.remove(url);
    _entries[url] = bytes;
    // Dart maps preserve insertion order, so the first key is the least
    // recently used.
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
    }
  }

  /// Forgets everything. Call on sign-out and when switching accounts.
  void clear() => _entries.clear();

  int get length => _entries.length;
}
