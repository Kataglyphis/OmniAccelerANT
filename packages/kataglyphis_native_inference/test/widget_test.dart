// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:kataglyphis_native_inference/main.dart';

void main() {
  testWidgets('App bootstrap smoke test', (WidgetTester tester) async {
    // Build the app and ensure the root widget can be mounted in test mode.
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    expect(find.byType(MyApp), findsOneWidget);
  });
}
