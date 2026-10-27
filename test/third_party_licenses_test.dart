@TestOn('vm')
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_accelerant/third_party_licenses.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'the shipped inventory lists native code and crates with their texts',
    () async {
      addTearDown(LicenseRegistry.reset);
      registerThirdPartyLicenses();
      final entries = await LicenseRegistry.licenses.toList();
      String textOf(String package) => entries
          .firstWhere((entry) => entry.packages.contains(package))
          .paragraphs
          .map((paragraph) => paragraph.text)
          .join('\n');

      expect(
        textOf('GStreamer (core, base, good, bad, plugins, editing services)'),
        contains('GNU LESSER GENERAL PUBLIC LICENSE'),
      );
      expect(textOf('Fraunhofer FDK AAC'), contains('Fraunhofer'));
      expect(
        entries.where(
          (entry) => entry.packages.any((name) => name.startsWith('serde ')),
        ),
        isNotEmpty,
      );
      expect(entries.length, greaterThan(300));
    },
  );
}
