// Frame timings of the app's main paths, through Flutter's own tooling: run by flutter drive --profile and test_driver/perf_driver.dart.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:omni_accelerant/main.dart';
import 'package:omni_accelerant/src/rust/frb_generated.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await RustLib.init();
  });

  testWidgets(
    'start, page switches and resizes stay within their frame budgets',
    (WidgetTester tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1100, 800);
      addTearDown(tester.view.reset);

      await binding.watchPerformance(() async {
        await tester.pumpWidget(const App());
        await tester.pumpAndSettle();
      }, reportKey: 'start');

      // Each tab in turn, three rounds: a page switch must not rebuild the app.
      Future<void> visit(IconData icon) async {
        await tester.tap(find.byIcon(icon).first);
        await tester.pumpAndSettle();
      }

      await binding.watchPerformance(() async {
        for (var round = 0; round < 3; round++) {
          await visit(Icons.tune_outlined);
          await visit(Icons.house_outlined);
          await visit(Icons.person_outlined);
          await visit(Icons.camera_enhance_outlined);
        }
      }, reportKey: 'page_switches');

      // Across both layout breakpoints and back, as a phone turns or a window is dragged.
      await binding.watchPerformance(() async {
        for (final width in <double>[800, 1200, 1600, 1250, 950, 600, 1100]) {
          tester.view.physicalSize = Size(width, 800);
          await tester.pumpAndSettle();
        }
      }, reportKey: 'resizes');
    },
  );
}
