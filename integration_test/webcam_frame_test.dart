import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:omni_accelerant/Pages/StreamPage/rust_webcam_view.dart';
import 'package:omni_accelerant/src/rust/api/webcam.dart';
import 'package:omni_accelerant/src/rust/frb_generated.dart';

/// A test-pattern frame travels Rust -> knt_push_frame -> the Linux texture; the push path needs no camera.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await RustLib.init();
  });

  testWidgets('a test-pattern frame reaches the native texture', (
    WidgetTester tester,
  ) async {
    // The lane runs this only with the Rust webcam features; a featureless build throws here, loudly.
    listCameras();

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Center(child: RustWebcamView(width: 320, height: 240)),
          ),
        ),
      ),
    );
    await _pumpUntil(tester, () => find.byType(Texture).evaluate().isNotEmpty);

    final Finder start = find.text('Start');
    await tester.ensureVisible(start);
    await tester.tap(start);
    await tester.pump();

    const MethodChannel channel = MethodChannel('kataglyphis_native_inference');
    bool pushed = false;
    final DateTime deadline = DateTime.now().add(const Duration(seconds: 60));
    while (!pushed && DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 250));
      await Future<void>.delayed(const Duration(milliseconds: 250));
      pushed = await channel.invokeMethod<bool>('hasPushedFrame') ?? false;
    }
    expect(
      pushed,
      isTrue,
      reason: 'no frame reached the texture through knt_push_frame in 60 s',
    );

    await tester.tap(find.text('Stop'));
    await tester.pump();
  }, skip: !Platform.isLinux);
}

/// Pumps until [done] holds; a texture id arrives over a platform channel, so pumpAndSettle cannot wait for it.
Future<void> _pumpUntil(WidgetTester tester, bool Function() done) async {
  final DateTime deadline = DateTime.now().add(const Duration(seconds: 30));
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('timed out waiting for the texture');
    }
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}
