@TestOn('vm')
library;

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_accelerant/src/boot/onnx_self_check.dart';
import 'package:omni_accelerant/src/rust/api/onnx.dart';
import 'package:omni_accelerant/src/rust/api/webcam.dart';
import 'package:omni_accelerant/src/rust/frb_generated.dart';

class _Detector extends Fake implements RustLibApi {
  bool fail = false;
  int profileCalls = 0;

  @override
  void crateApiOnnxProfileDetectorImage({
    required String imagePath,
    required String output,
    required String repeatOutput,
    required String profile,
  }) {
    expect(
      (imagePath, output, repeatOutput, profile),
      ('image.jpg', 'first.json', 'second.json', 'profile'),
    );
    profileCalls++;
    if (fail) throw StateError('profile failed');
  }

  @override
  List<Detection> crateApiOnnxDetectPersonsRgba({
    required String modelPath,
    required List<int> rgba,
    required int width,
    required int height,
    required double scoreThreshold,
  }) {
    expect(modelPath, isEmpty);
    expect((width, height, scoreThreshold), (64, 64, 0.5));
    expect(rgba.length, 64 * 64 * 4);
    expect(rgba.every((int value) => value == 0), isTrue);
    if (fail) throw StateError('model unavailable');
    return <Detection>[];
  }

  List<double> catScores = const <double>[];

  @override
  List<DetectionBox> crateApiOnnxDetectRgba({
    required List<int> rgba,
    required int width,
    required int height,
    required Int64List classes,
  }) {
    expect(<int>[for (final c in classes) c.toInt()], <int>[15]);
    expect((rgba.length, width, height), (2 * 3 * 4, 2, 3));
    return <DetectionBox>[
      for (final double score in catScores)
        DetectionBox(
          x1: 0,
          y1: 0,
          x2: 1,
          y2: 1,
          score: score,
          classId: PlatformInt64Util.from(15),
        ),
    ];
  }
}

void main() {
  final _Detector detector = _Detector();
  setUpAll(() => RustLib.initMock(api: detector));
  setUp(() {
    detector.fail = false;
    detector.profileCalls = 0;
  });

  test('the detect check counts only cats at score 0.4 or more', () {
    final Uint8List frame = Uint8List(2 * 3 * 4);
    detector.catScores = const <double>[0.95, 0.4, 0.39];
    expect(countConfidentCats(frame, 2, 3), 2);
    detector.catScores = const <double>[];
    expect(countConfidentCats(frame, 2, 3), 0);
    expect(detectCheckMinimum, 2);
  });

  test('runs inference through the detector bridge', () {
    expect(runOnnxSelfCheck(), 0);
  });

  test('reports model loading failures to the caller', () {
    detector.fail = true;
    expect(runOnnxSelfCheck, throwsStateError);
  });

  test('requires all profile arguments and forwards them to the bridge', () {
    expect(
      () => runProfiledDetector(['--onnx-profile-image']),
      throwsArgumentError,
    );
    expect(detector.profileCalls, 0);
    runProfiledDetector([
      '--onnx-profile-image',
      'image.jpg',
      'first.json',
      'second.json',
      'profile',
    ]);
    expect(detector.profileCalls, 1);
    detector.fail = true;
    expect(
      () => runProfiledDetector([
        '--onnx-profile-image',
        'image.jpg',
        'first.json',
        'second.json',
        'profile',
      ]),
      throwsStateError,
    );
  });
}
