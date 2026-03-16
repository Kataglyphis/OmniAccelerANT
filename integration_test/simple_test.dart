import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kataglyphis_inference_engine/main.dart';
import 'package:kataglyphis_inference_engine/src/rust/frb_generated.dart';

/// Integration tests for the Kataglyphis Inference Engine application.
///
/// These tests verify that the app can properly initialize and interact
/// with native Rust code through Flutter Rust Bridge.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await RustLib.init();
  });

  group('App Initialization', () {
    testWidgets('App widget mounts successfully', (WidgetTester tester) async {
      await tester.pumpWidget(const App());
      await tester.pumpAndSettle();

      // Verify the app has loaded by checking for a basic widget
      expect(find.byType(App), findsOneWidget);
    });
  });
}
