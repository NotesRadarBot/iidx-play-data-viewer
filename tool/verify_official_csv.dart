import 'dart:io';

import '../lib/repository.dart';
import '../lib/models.dart';

void main(List<String> args) {
  if (args.length != 2) {
    throw ArgumentError('Usage: dart run tool/verify_official_csv.dart <csv-path> <sp|dp>');
  }
  final style = args[1].toLowerCase() == 'dp' ? PlayStyle.dp : PlayStyle.sp;
  final summary = AppRepository().importOfficialCsv(File(args.first).readAsStringSync(), style: style);
  if (summary.errors.isNotEmpty || summary.chartCount == 0) {
    throw StateError('CSV import failed: ${summary.errors.join(' / ')}');
  }
  print('${style.label}: songs=${summary.songCount}, charts=${summary.chartCount}, skipped=${summary.skippedRows}');
}
