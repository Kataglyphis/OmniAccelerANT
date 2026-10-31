import 'dart:typed_data';

import 'package:omni_accelerant/src/rust/api/onnx.dart';

/// Runs the configured detector on a blank frame; it does not prove GPU placement.
int runOnnxSelfCheck() => detectPersonsRgba(
  modelPath: '',
  rgba: Uint8List(64 * 64 * 4),
  width: 64,
  height: 64,
  scoreThreshold: 0.5,
).length;

/// Profiles two detections in the same packaged detector session.
void runProfiledDetector(List<String> args) {
  if (args.length != 5 || args.first != '--onnx-profile-image') {
    throw ArgumentError(
      'Expected image, two output paths and a profile prefix.',
    );
  }
  profileDetectorImage(
    imagePath: args[1],
    output: args[2],
    repeatOutput: args[3],
    profile: args[4],
  );
}
