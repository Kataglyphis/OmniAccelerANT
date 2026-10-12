// The whole app at a phone's, a tablet's and a desktop's size: a layout that breaks at one width alone failed only the slow Linux integration test.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_accelerant/main.dart';

const List<Size> _sizes = <Size>[
  Size(360, 800),
  Size(800, 1000),
  Size(1280, 900),
];

/// The theme's Roboto, so text measures as in the app: the test font's square glyphs overflow rows real text fits.
Future<void> _loadRealFonts() async {
  const String dir = 'packages/anthology/assets/fonts/Roboto';
  final FontLoader roboto = FontLoader('packages/anthology/Roboto');
  for (final String face in <String>['Regular', 'Medium', 'Bold', 'Italic']) {
    roboto.addFont(rootBundle.load('$dir/Roboto-$face.ttf'));
  }
  await roboto.load();
}

void main() {
  setUpAll(_loadRealFonts);

  for (final Size size in _sizes) {
    testWidgets(
      'the app lays out at ${size.width.toInt()}x${size.height.toInt()}',
      (WidgetTester tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.runAsync(() async {
          await tester.pumpWidget(const App());
          // The bootstrap reads its settings off the asset bundle, which is real I/O.
          await Future<void>.delayed(const Duration(seconds: 1));
        });
        for (int i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(tester.takeException(), isNull);
        expect(find.byType(Scaffold), findsWidgets);
      },
    );
  }
}
