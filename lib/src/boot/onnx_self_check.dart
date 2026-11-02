import 'dart:convert';
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

/// The detector's warm p50 and p95 as the JSON line `quality-report.sh --perf-host` reads.
String latencyLine(List<double> milliseconds) {
  final List<double> ranked = List<double>.of(milliseconds)..sort();
  double rank(double fraction) =>
      ranked[(fraction * ranked.length).floor().clamp(0, ranked.length - 1)];
  return jsonEncode(<String, double>{
    'p50_ms': rank(0.5),
    'p95_ms': rank(0.95),
  });
}

/// Times [runs] cat detections through the bridge, after a warm-up, on an encoded image.
Future<String> runDetectLatency(Uint8List encoded, int runs) async {
  const int warmRuns = 5;
  final ui.Codec codec = await ui.instantiateImageCodec(encoded);
  final ui.Image image = (await codec.getNextFrame()).image;
  final ByteData? data = await image.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  );
  if (data == null) throw StateError('the image did not decode to RGBA');
  final Uint8List rgba = data.buffer.asUint8List(
    data.offsetInBytes,
    data.lengthInBytes,
  );
  final List<double> samples = <double>[];
  for (int run = 0; run < warmRuns + runs; run++) {
    final Stopwatch watch = Stopwatch()..start();
    countConfidentCats(rgba, image.width, image.height);
    if (run >= warmRuns) {
      samples.add(watch.elapsedMicroseconds / 1000);
    }
  }
  return latencyLine(samples);
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
