import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:omni_accelerant/main.dart';
import 'package:omni_accelerant/src/rust/frb_generated.dart';

/// The app initializes and mounts with the Rust bridge loaded.
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
