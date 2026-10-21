// Keeps integration_test/performance_test.dart's frame timings in out/perf/frontend.json for ANTfrastructure's frontend-perf-report.py.
import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  responseDataCallback: (Map<String, dynamic>? data) async {
    if (data == null) {
      return;
    }
    final out = File('out/perf/frontend.json')..createSync(recursive: true);
    out.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(data));
    stdout.writeln('frame timings: ${out.path}');
  },
);
