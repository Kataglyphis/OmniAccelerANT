// Windows, and Linux built with the Rust features, hand the camera to the Rust view; the page itself must then leave the plugin alone.
@TestOn('vm')
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_accelerant/Pages/StreamPage/rust_webcam_view.dart';
import 'package:omni_accelerant/Pages/StreamPage/stream_page.dart';
import 'package:omni_accelerant/main.dart';
import 'package:omni_accelerant/src/rust/api/webcam.dart';
import 'package:omni_accelerant/src/rust/frb_generated.dart';

import 'support/real_fonts.dart';

/// The Rust core of a build with the webcam features: no camera attached.
class _FakeRustApi extends Fake implements RustLibApi {
  int listed = 0;
  int stops = 0;

  @override
  List<CameraDesc> crateApiWebcamListCameras() {
    listed++;
    return const <CameraDesc>[];
  }

  @override
  void crateApiWebcamStopWebcamInference() => stops++;
}

/// Boots the app on the Stream page with [calls] recording the plugin's channel.
Future<void> _pumpApp(WidgetTester tester, List<MethodCall> calls) async {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    StreamPageState.channel,
    (MethodCall call) async {
      calls.add(call);
      return call.method == 'create' ? 7 : null;
    },
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

void main() {
  final _FakeRustApi rust = _FakeRustApi();
  setUpAll(() async {
    RustLib.initMock(api: rust);
    await loadRealFonts();
  });

  for (final TargetPlatform platform in <TargetPlatform>[
    TargetPlatform.windows,
    TargetPlatform.linux,
  ]) {
    testWidgets(
      '${platform.name} hands the camera to the Rust view, which alone creates the texture',
      (WidgetTester tester) async {
        final List<MethodCall> calls = <MethodCall>[];
        await _pumpApp(tester, calls);

        expect(find.byType(RustWebcamView), findsOneWidget);
        expect(find.text('Webcam Live Inference (Rust)'), findsOneWidget);
        // One create, the view's: a second from the page would race it for the plugin's single texture.
        expect(calls.map((MethodCall c) => c.method), <String>['create']);
        if (platform == TargetPlatform.linux) {
          expect(rust.listed, greaterThan(0), reason: 'Linux probes the core');
        }

        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }

  test('the variant leaves no platform override behind', () {
    expect(debugDefaultTargetPlatformOverride, isNull);
  });
}
