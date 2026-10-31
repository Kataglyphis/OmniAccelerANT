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
