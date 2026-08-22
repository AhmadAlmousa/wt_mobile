import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/core/webtrees_client.dart';

/// The app states its version in three places, and they have drifted apart
/// before: the User-Agent said `0.1`, `pubspec.yaml` said `1.0.0` and the APK
/// said `0.1.0`. That matters more than tidiness — the User-Agent is what a
/// site administrator sees in their access log, so a build that misreports
/// itself makes their log misleading about which release did what.
///
/// Now that the version is bumped at every milestone, this is the check that
/// keeps the ritual honest.
void main() {
  test('the User-Agent version matches pubspec.yaml', () {
    final declared = RegExp(
      r'^version:\s*(\d+\.\d+\.\d+)',
      multiLine: true,
    ).firstMatch(File('pubspec.yaml').readAsStringSync())?.group(1);

    expect(declared, isNotNull, reason: 'pubspec.yaml has no version');
    expect(
      kAppVersion,
      declared,
      reason: 'bump lib/core/webtrees_client.dart with pubspec.yaml',
    );
  });

  test('the agent still says who it is without pretending to be a browser', () {
    // webtrees serves a cookie-challenge stub instead of the page to anything
    // claiming to be Chrome, Firefox, Safari or Opera.
    expect(kUserAgent, contains(kAppVersion));
    for (final browser in const ['Chrome/', 'Firefox/', 'Safari/', 'Opera/']) {
      expect(kUserAgent, isNot(contains(browser)));
    }
  });
}
