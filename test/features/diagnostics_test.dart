import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/app/theme.dart';
import 'package:webtrees_mobile/core/webtrees_url.dart';
import 'package:webtrees_mobile/data/capabilities.dart';
import 'package:webtrees_mobile/data/diagnostics.dart';
import 'package:webtrees_mobile/data/module/module_api.dart';
import 'package:webtrees_mobile/data/session_manager.dart';
import 'package:webtrees_mobile/domain/instance.dart';
import 'package:webtrees_mobile/domain/notice.dart';
import 'package:webtrees_mobile/features/shared/diagnostics_screen.dart';
import 'package:webtrees_mobile/l10n/app_localizations.dart';

WebtreesInstance _site({
  String version = '2.2.6',
  ServerHealth health = ServerHealth.ok,
  List<Notice> warnings = const [],
}) => WebtreesInstance(
  url: WebtreesUrl(
    base: Uri.parse('https://tree.example.com'),
    style: UrlStyle.pretty,
  ),
  version: version,
  health: health,
  warnings: warnings,
);

ModuleCapabilities _module({Set<String> features = const {}}) =>
    ModuleCapabilities(
      apiVersion: kModuleApiVersion,
      moduleVersion: '1.1.0',
      webtreesVersion: '2.3.0-dev',
      features: features,
      languages: const {'ar', 'en-GB'},
    );

void main() {
  group('the report', () {
    test('says what a maintainer needs and nothing they should not have', () {
      final report = Diagnostics(
        stage: ConnectionStage.signedIn,
        instance: _site(warnings: const [VersionUnreadable()]),
        username: 'mobile',
        capabilities: _module(features: const {Capability.individual}),
      ).report;

      // The three that decide which code path ran on a real site.
      expect(report, contains('https://tree.example.com'));
      expect(report, contains('address style: pretty'));
      expect(report, contains('webtrees: 2.2.6'));

      // Which transport answered, per capability, because "the module is
      // installed" and "this screen used it" are different questions.
      expect(report, contains('individual=module'));
      expect(report, contains('ancestors=pages'));

      // What the site could not tell the app.
      expect(report, contains('site version unreadable'));

      // Nothing a bug report should never carry.
      expect(report, isNot(contains('password')));
      expect(report, isNot(contains('WT-ID')));
    });

    test('a site with no module says so plainly', () {
      final report = Diagnostics(
        stage: ConnectionStage.signedIn,
        instance: _site(),
        username: 'mobile',
        capabilities: ModuleCapabilities.none,
      ).report;

      expect(report, contains('module: not installed'));
      // Everything falls back, so every line reads the same way.
      expect(report, contains('access=pages'));
      expect(report, contains('statistics=pages'));
    });

    test('a connection that never got anywhere still reports', () {
      // The state somebody most wants a diagnostics screen in: an address was
      // typed and nothing came back.
      final report = Diagnostics(
        stage: ConnectionStage.disconnected,
        instance: null,
        username: null,
        capabilities: ModuleCapabilities.none,
      ).report;

      expect(report, contains('site: none connected'));
      expect(report, contains('connection: disconnected'));
    });
  });

  group('the screen', () {
    Future<void> open(WidgetTester tester, Diagnostics diagnostics) async {
      tester.view.physicalSize = const Size(1000, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppText.localizationsDelegates,
          supportedLocales: AppText.supportedLocales,
          theme: AppTheme.light(const Locale('en')),
          home: DiagnosticsScreen(diagnostics: diagnostics),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('names each capability’s transport', (tester) async {
      await open(
        tester,
        Diagnostics(
          stage: ConnectionStage.signedIn,
          instance: _site(),
          username: 'mobile',
          capabilities: _module(
            features: const {Capability.individual, Capability.access},
          ),
        ),
      );

      // Two answered by the module, six by the site's own pages.
      expect(find.text('Module'), findsNWidgets(2));
      expect(find.text('Site pages'), findsNWidgets(6));
    });

    testWidgets('a capability read from the page says so, module or not', (
      tester,
    ) async {
      // The screen exists to answer "which transport answered this", and
      // statistics is the one capability a module can offer and still not
      // answer: it sends four sections where the page publishes seventeen.
      // Reporting the module here would send a reader looking in the wrong
      // place for a figure they disagreed with.
      await open(
        tester,
        Diagnostics(
          stage: ConnectionStage.signedIn,
          instance: _site(),
          username: 'mobile',
          capabilities: _module(
            features: const {Capability.statistics, Capability.individual},
          ),
        ),
      );

      expect(find.text('Module'), findsOneWidget);
      expect(find.text('Site pages'), findsNWidgets(7));
    });

    testWidgets('a site with no module does not pretend otherwise', (
      tester,
    ) async {
      await open(
        tester,
        Diagnostics(
          stage: ConnectionStage.signedIn,
          instance: _site(),
          username: 'mobile',
          capabilities: ModuleCapabilities.none,
        ),
      );

      expect(find.textContaining('Not installed'), findsOne);
      expect(find.text('Module'), findsNothing);
    });

    testWidgets('an unread version is stated, not left blank', (tester) async {
      await open(
        tester,
        Diagnostics(
          stage: ConnectionStage.connecting,
          instance: _site(version: '', health: ServerHealth.degraded),
          username: null,
          capabilities: ModuleCapabilities.none,
        ),
      );

      expect(find.text('Could not be read'), findsOne);
      expect(find.textContaining('missing optional PHP'), findsOne);
    });
  });
}
