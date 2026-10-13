// Windows, and Linux built with the Rust features, hand the camera to the Rust view; the page itself must then leave the plugin alone.
@TestOn('vm')
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_accelerant/Pages/StreamPage/rust_webcam_view.dart';
import 'package:omni_accelerant/src/rust/api/webcam.dart';
import 'package:omni_accelerant/src/rust/frb_generated.dart';

import 'support/real_fonts.dart';
import 'support/stream_page_app.dart';

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
        await pumpStreamPageApp(tester, (MethodCall call) async {
          calls.add(call);
          return call.method == 'create' ? 7 : null;
        });

        expect(find.byType(RustWebcamView), findsOneWidget);
        expect(find.text('Webcam Live Inference (Rust)'), findsOneWidget);
        // One create, the view's: a second from the page would race it for the plugin's single texture.
        expect(calls.map((MethodCall c) => c.method), <String>['create']);
        if (platform == TargetPlatform.linux) {
          expect(rust.listed, greaterThan(0), reason: 'Linux probes the core');
        }

        await unmountApp(tester);
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }

  test('the variant leaves no platform override behind', () {
    expect(debugDefaultTargetPlatformOverride, isNull);
  });
}
