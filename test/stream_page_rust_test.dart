// Windows and Linux hand the camera to the Rust view; the page itself must then leave the plugin alone.
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

/// The Rust core of a desktop build: no camera attached.
class _FakeRustApi extends Fake implements RustLibApi {
  int probed = 0;
  int listed = 0;
  int stops = 0;

  @override
  bool crateApiWebcamWebcamInferenceAvailable() {
    probed++;
    return true;
  }

  @override
  Future<List<CameraDesc>> crateApiWebcamListCameras() async {
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
        expect(rust.probed, 0, reason: 'the target decides, not a probe');
        // Enumerating cameras starts libcamera, which held the first frame ~1 s while the page did it.
        expect(rust.listed, 0, reason: 'the page enumerated cameras');

        await unmountApp(tester);
        // No pipeline of the page's own to stop: the Rust view owns the camera.
        expect(calls.map((MethodCall c) => c.method), <String>['create']);
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }

  test('the variant leaves no platform override behind', () {
    expect(debugDefaultTargetPlatformOverride, isNull);
  });
}
