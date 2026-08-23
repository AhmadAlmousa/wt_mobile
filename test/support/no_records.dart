import 'dart:typed_data';

import 'package:webtrees_mobile/data/transport.dart';
import 'package:webtrees_mobile/domain/charts.dart';
import 'package:webtrees_mobile/domain/records.dart';

/// A transport that is never asked anything.
///
/// For the tests that draw people rather than fetch them: a chart box or a
/// list row needs a transport only so it can go looking for a photograph, and
/// a person with no photograph never does.
class NoRecords implements RecordsTransport {
  const NoRecords();

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
