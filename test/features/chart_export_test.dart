import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/app/theme.dart';
import 'package:webtrees_mobile/data/transport.dart';
import 'package:webtrees_mobile/domain/charts.dart';
import 'package:webtrees_mobile/domain/records.dart';
import 'package:webtrees_mobile/features/charts/chart_canvas.dart';
import 'package:webtrees_mobile/features/charts/chart_layout.dart';
import 'package:webtrees_mobile/features/charts/chart_options.dart';
import 'package:webtrees_mobile/features/charts/chart_pdf.dart';
import 'package:webtrees_mobile/features/charts/fan_layout.dart';

/// A transport that is never asked anything: a chart with no photographs on
/// it fetches nothing.
class _NoRecords implements RecordsTransport {
  @override
  Future<Uint8List> image(String url) async => Uint8List(0);

  @override
  Future<IndividualRecord> individual(String tree, String xref) =>
      throw UnimplementedError();

  @override
  Future<SearchPage> search(String tree, String query, {int page = 1}) =>
      throw UnimplementedError();

  @override
  Future<Map<ChartKind, String>> treeCharts(String tree) =>
      throw UnimplementedError();
}

AncestorNode _line(
  String xref, {
  int sosa = 1,
  List<AncestorNode> parents = const [],
}) => AncestorNode(
  person: PersonRef(
    xref: xref,
    name: 'اسم $xref',
    sex: Sex.male,
    isDeceased: true,
    lifespan: '1901–1974',
  ),
  sosa: sosa,
  parents: parents,
);

/// Five generations, which is far wider than any phone.
AncestorNode _deepTree() {
  AncestorNode build(int depth, int sosa) => _line(
    'X$sosa',
    sosa: sosa,
    parents: depth == 0
        ? const []
        : [build(depth - 1, sosa * 2), build(depth - 1, sosa * 2 + 1)],
  );
  return build(4, 1);
}

void main() {
  final layout = layoutAncestors(_deepTree());

  group('exporting a chart', () {
    testWidgets('captures the whole chart, not the window onto it', (
      tester,
    ) async {
      final capture = GlobalKey();
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(const Locale('en')),
          home: Scaffold(
            body: ChartCanvas(
              layout: layout,
              records: _NoRecords(),
              captureKey: capture,
              onTapPerson: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final object =
          capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;

      // The chart is drawn far larger than the phone it is being read on, and
      // that is exactly what has to reach the file: a boundary around the
      // viewport would answer the size of the window instead.
      expect(object.size.width, greaterThan(800));
      expect(object.size.width, layout.size.width + ChartViewport.margin * 2);
      expect(object.size.height, layout.size.height + ChartViewport.margin * 2);
    });
  });

  group('a chart as a page', () {
    final ink = ChartInk(
      colors: AppTheme.light(const Locale('ar')).colorScheme,
      people: PersonColors.light,
    );

    test('is drawn as shapes and text rather than as a picture', () async {
      final bytes = await boxChartPage(
        layout: layout,
        options: const ChartOptions(),
        ink: ink,
        title: 'أسلاف',
      );
      final raw = latin1.decode(bytes, allowInvalid: true);

      expect(raw.startsWith('%PDF'), isTrue);
      // A font is embedded, which is only worth doing if the names on the
      // page are text. A screenshot needs no font at all.
      expect(raw, contains('/FontFile2'));
      // And nothing on the page is a bitmap: a chart with the photographs
      // turned off is entirely vector.
      expect(raw, isNot(contains('/Subtype /Image')));
    });

    test('draws the fan the same way', () async {
      final bytes = await fanChartPage(
        layout: layoutFan(_deepTree()),
        ink: ink,
        title: 'مروحة',
      );
      final raw = latin1.decode(bytes, allowInvalid: true);

      expect(raw.startsWith('%PDF'), isTrue);
      expect(raw, contains('/FontFile2'));
      expect(raw, isNot(contains('/Subtype /Image')));
    });
  });
}
