// The whole app at a phone's, a tablet's and a desktop's size, and at a large system font: a layout that breaks at one width alone failed only the slow Linux integration test.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:omni_accelerant/main.dart';

import 'support/real_fonts.dart';

/// The bottom bar's four pages, a markdown footer page and a blog post.
const List<String> _routes = <String>[
  '/stream',
  '/cameraSettings',
  '/landingPage',
  '/aboutMe',
  '/privacyPolicy',
  '/aiBlog',
];

/// Phone, tablet and desktop, and a phone at 150 % and 200 % system font (Android's largest), and a desktop at 200 %.
const List<(Size, double)> _cases = <(Size, double)>[
  (Size(360, 800), 1),
  (Size(800, 1000), 1),
  (Size(1280, 900), 1),
  (Size(360, 800), 1.5),
  (Size(360, 800), 2),
  (Size(1280, 900), 2),
];

void main() {
  setUpAll(loadRealFonts);

  for (final (Size size, double textScale) in _cases) {
    testWidgets(
      'every main page lays out at ${size.width.toInt()}x${size.height.toInt()}, text x$textScale',
      (WidgetTester tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = textScale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        addTearDown(tester.view.reset);
        await tester.runAsync(() async {
          await tester.pumpWidget(const App());
          // The bootstrap reads its settings off the asset bundle, which is real I/O.
          await Future<void>.delayed(const Duration(seconds: 1));
        });
        for (int i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.byType(Scaffold), findsWidgets);
        for (final String route in _routes) {
          GoRouter.of(tester.element(find.byType(Scaffold).first)).go(route);
          // Pages read markdown and JSON off the asset bundle too.
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 500)),
          );
          for (int i = 0; i < 5; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(tester.takeException(), isNull, reason: route);
        }
        // markdown_widget's VisibilityDetector re-arms a 500 ms timer while its pages live: unmount them, then let it run out.
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      },
    );
  }
}
