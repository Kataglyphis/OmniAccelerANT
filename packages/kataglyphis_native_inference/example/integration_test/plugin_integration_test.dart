// An integration test, since only a full app reaches the plugin's host side.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:kataglyphis_native_inference/kataglyphis_native_inference.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('getPlatformVersion test', (WidgetTester tester) async {
    final KataglyphisNativeInference plugin = KataglyphisNativeInference();
    final String? version = await plugin.getPlatformVersion();
    // The string depends on the host, so only non-emptiness is asserted.
    expect(version?.isNotEmpty, true);
  });
}
