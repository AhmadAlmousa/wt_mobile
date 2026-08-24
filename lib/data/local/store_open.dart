/// Where the store lives on a device.
///
/// The one file in `data/local/` that needs Flutter, kept apart for that
/// reason: `store.dart` is a schema and a schema should be openable by
/// anything, including a plain Dart tool with no engine
/// (`tool/live_check.dart` fills a real store to check the sync).
library;

import 'package:drift_flutter/drift_flutter.dart';

import 'store.dart';

/// Opens this device's copy of the tree.
///
/// `driftDatabase` puts the file where each platform keeps application
/// support data and opens it with `NativeDatabase.createInBackground`, so
/// every statement runs on its own isolate. That matters more here than in
/// most apps: a first sync writes 1,463 records, and the isolate is what keeps
/// that off the thread drawing the screen.
LocalStore openLocalStore() => LocalStore(driftDatabase(name: 'webtrees_tree'));
