import 'package:flutter_test/flutter_test.dart';

import 'package:omni_accelerant/main.dart';

void main() {
  testWidgets('App bootstrap smoke test', (WidgetTester tester) async {
    // Build the app and ensure the root widget can be mounted in test mode.
    await tester.pumpWidget(const App());
    await tester.pump();

    expect(find.byType(App), findsOneWidget);
  });
}
