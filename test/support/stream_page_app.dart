import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_accelerant/Pages/StreamPage/stream_page.dart';
import 'package:omni_accelerant/main.dart';

/// Boots the app on its start page, the Stream page, with [plugin] answering the native plugin's channel.
Future<void> pumpStreamPageApp(
  WidgetTester tester,
  Future<Object?> Function(MethodCall call) plugin,
) async {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    StreamPageState.channel,
    plugin,
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      StreamPageState.channel,
      null,
    ),
  );
  tester.view.physicalSize = const Size(1280, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.runAsync(() async {
    await tester.pumpWidget(const App());
    // The bootstrap reads its settings off the asset bundle, which is real I/O.
    await Future<void>.delayed(const Duration(seconds: 1));
  });
  for (int i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Unmounts the app, which stops the pipeline, and lets the timers it leaves run out.
Future<void> unmountApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}
