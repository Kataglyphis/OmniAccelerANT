import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show Int64List;
import 'package:omni_accelerant/src/rust/api/onnx.dart';

/// The cats `--detect-check` must find in its photo, each at [detectCheckScore] or more.
const int detectCheckMinimum = 2;
const double detectCheckScore = 0.4;
const int _catClass = 15;

/// Cats at [detectCheckScore] or more in an RGBA frame, through the bridge's class filter.
int countConfidentCats(Uint8List rgba, int width, int height) => detectRgba(
  rgba: rgba,
  width: width,
  height: height,
  classes: Int64List.fromList(<int>[_catClass]),
).where((box) => box.score >= detectCheckScore).length;

/// Decodes an encoded image with the engine's codecs and counts its confident cats.
Future<int> runDetectCheck(Uint8List encoded) async {
  final ui.Codec codec = await ui.instantiateImageCodec(encoded);
  final ui.Image image = (await codec.getNextFrame()).image;
  final ByteData? rgba = await image.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  );
  if (rgba == null) throw StateError('the image did not decode to RGBA');
  return countConfidentCats(
    rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes),
    image.width,
    image.height,
  );
}

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
