@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_accelerant/src/boot/onnx_self_check.dart';
import 'package:omni_accelerant/src/rust/api/onnx.dart';
import 'package:omni_accelerant/src/rust/frb_generated.dart';

class _Detector extends Fake implements RustLibApi {
  bool fail = false;

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
}

void main() {
  final _Detector detector = _Detector();
  setUpAll(() => RustLib.initMock(api: detector));
  setUp(() => detector.fail = false);

  test('runs inference through the detector bridge', () {
    expect(runOnnxSelfCheck(), 0);
  });

  test('reports model loading failures to the caller', () {
    detector.fail = true;
    expect(runOnnxSelfCheck, throwsStateError);
  });
}
