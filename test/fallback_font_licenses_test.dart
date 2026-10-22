@TestOn('vm')
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_accelerant/fallback_font_licenses.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the shipped fallback fonts appear with their OFL notice', () async {
    addTearDown(LicenseRegistry.reset);
    registerFallbackFontLicenses();
    final entry = await LicenseRegistry.licenses
        .where((entry) => entry.packages.contains('Noto Sans Symbols 2'))
        .first;
    expect(entry.packages, contains('Noto Color Emoji'));
    final text = entry.paragraphs.map((paragraph) => paragraph.text).join('\n');
    expect(text, contains('SIL OPEN FONT LICENSE Version 1.1'));
    expect(text, contains('Noto Color Emoji: Copyright 2013 Google LLC'));
    expect(text, contains('Noto Sans Symbols 2: Copyright 2022'));
  });
}
