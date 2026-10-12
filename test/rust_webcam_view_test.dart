// The Windows and Linux camera page talks to the Rust core and the plugin's texture; only the Linux lane's Xvfb run reached it before.
@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_accelerant/Pages/StreamPage/rust_webcam_view.dart';
import 'package:omni_accelerant/src/rust/api/webcam.dart';
import 'package:omni_accelerant/src/rust/frb_generated.dart';

const MethodChannel _plugin = MethodChannel('kataglyphis_native_inference');

/// Stands in for the Rust core's webcam API: hands out cameras and records every session.
class _FakeRustApi extends Fake implements RustLibApi {
  List<CameraDesc> cameras = const <CameraDesc>[];
  Object? listError;
  final List<WebcamStreamConfig> started = <WebcamStreamConfig>[];
  int stops = 0;
  StreamController<DetectionEvent>? session;

  void reset() {
    cameras = const <CameraDesc>[];
    listError = null;
    started.clear();
    stops = 0;
    session = null;
  }

  @override
  List<CameraDesc> crateApiWebcamListCameras() {
    final Object? error = listError;
    if (error != null) throw error;
    return cameras;
  }

  @override
  Stream<DetectionEvent> crateApiWebcamStartWebcamInference({
    required WebcamStreamConfig config,
  }) {
    started.add(config);
    session = StreamController<DetectionEvent>();
    return session!.stream;
  }

  @override
  void crateApiWebcamStopWebcamInference() => stops++;
}

DetectionEvent _event({required int boxes, double fps = 0, double ms = 0}) =>
    DetectionEvent(
      detections: <DetectionBox>[
        for (int i = 0; i < boxes; i++)
          DetectionBox(x1: 10, y1: 10, x2: 50, y2: 50, score: 0.8, classId: 15),
      ],
      frameSequence: BigInt.one,
      ptsMs: null,
      inferenceMs: ms,
      fps: fps,
    );

/// Mounts the view at 640x480; `create` answers [textureId], or fails when it is null.
Future<List<MethodCall>> _pump(
  WidgetTester tester, {
  int? textureId = 9,
}) async {
  final List<MethodCall> calls = <MethodCall>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_plugin, (
    MethodCall call,
  ) async {
    calls.add(call);
    if (textureId == null) {
      throw PlatformException(code: 'texture', message: 'no registrar');
    }
    return textureId;
  });
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _plugin,
      null,
    ),
  );
  tester.view.physicalSize = const Size(1280, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: RustWebcamView(width: 640, height: 480),
        ),
      ),
    ),
  );
  await tester.pump();
  return calls;
}

void main() {
  final _FakeRustApi rust = _FakeRustApi();
  setUpAll(() => RustLib.initMock(api: rust));
  setUp(rust.reset);

  testWidgets('Start streams the test pattern into the texture it created', (
    WidgetTester tester,
  ) async {
    final List<MethodCall> calls = await _pump(tester);
    expect(calls.single.method, 'create');
    expect(calls.single.arguments, <int>[640, 480]);
    expect(find.byType(Texture), findsOneWidget);
    expect(find.textContaining('Stopped • 0.0 fps'), findsOneWidget);

    await tester.enterText(find.byType(TextField), ' models/cat.onnx ');
    await tester.tap(find.text('Start'));
    await tester.pump();

    final WebcamStreamConfig config = rust.started.single;
    expect(config.useTestSource, isTrue);
    expect(config.deviceIndex, isNull);
    expect((config.width, config.height, config.framerate), (640, 480, 30));
    expect(config.modelPath, 'models/cat.onnx');
    expect(config.scoreThreshold, 0.5);
    expect(config.textureId, 9);

    rust.session!.add(_event(boxes: 2, fps: 29.5, ms: 12.3));
    await tester.pump();
    expect(
      find.text('Running • 29.5 fps • 12.3 ms inference • 2 detection(s)'),
      findsOneWidget,
    );

    final int stopsBefore = rust.stops;
    await tester.tap(find.text('Stop'));
    await tester.pump();
    expect(rust.stops, stopsBefore + 1);
    expect(rust.session!.hasListener, isFalse);
    expect(find.textContaining('Stopped'), findsOneWidget);
  });

  testWidgets('Webcam asks the core for cameras and streams the first one', (
    WidgetTester tester,
  ) async {
    rust.cameras = const <CameraDesc>[
      CameraDesc(index: 2, name: 'C270'),
      CameraDesc(index: 5, name: 'Pi camera'),
    ];
    await _pump(tester);

    await tester.tap(find.text('Webcam'));
    await tester.pump();
    expect(find.text('2: C270'), findsOneWidget);

    await tester.tap(find.text('Start'));
    await tester.pump();
    expect(rust.started.single.useTestSource, isFalse);
    expect(rust.started.single.deviceIndex, 2);
  });

  testWidgets('a failed enumeration and a failed session show their error', (
    WidgetTester tester,
  ) async {
    rust.listError = 'no V4L2 devices';
    await _pump(tester);

    await tester.tap(find.byTooltip('Refresh cameras'));
    await tester.pump();
    expect(
      find.text('Camera enumeration failed: no V4L2 devices'),
      findsOneWidget,
    );

    await tester.tap(find.text('Start'));
    await tester.pump();
    rust.session!.addError('the pipeline stopped');
    await tester.pump();
    expect(find.text('the pipeline stopped'), findsOneWidget);
    expect(find.textContaining('Stopped'), findsOneWidget);
  });

  testWidgets('without a texture Start says so and starts nothing', (
    WidgetTester tester,
  ) async {
    await _pump(tester, textureId: null);
    expect(find.text('Texture creation failed: no registrar'), findsOneWidget);
    expect(find.byType(Texture), findsNothing);

    await tester.tap(find.text('Start'));
    await tester.pump();
    expect(find.text('No texture yet — cannot start'), findsOneWidget);
    expect(rust.started, isEmpty);
  });

  testWidgets('leaving the page stops the core', (WidgetTester tester) async {
    await _pump(tester);
    await tester.tap(find.text('Start'));
    await tester.pump();
    final int stopsBefore = rust.stops;

    await tester.pumpWidget(const SizedBox());
    expect(rust.stops, stopsBefore + 1);
    expect(rust.session!.hasListener, isFalse);
  });
}
