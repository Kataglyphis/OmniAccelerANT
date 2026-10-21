/// The plugin's GStreamer pipelines on Android and macOS, per source, and the order the Stream page tries sources in.
library;

import 'package:flutter/foundation.dart';

/// Default framerate for non-Android platforms (frames per second).
const int kDefaultFramerate = 30;

/// Pixel format used for video conversion (RGBA for cross-platform compatibility).
const String kPixelFormat = 'RGBA';

// Pipeline Builder

/// Builds GStreamer pipeline strings per video source and platform.
class GStreamerPipelineBuilder {
  /// Creates a pipeline builder with the specified dimensions and framerate.
  const GStreamerPipelineBuilder({
    required this.width,
    required this.height,
    required this.fps,
    required this.isAndroid,
  });

  /// Video width in pixels.
  final int width;

  /// Video height in pixels.
  final int height;

  /// Target framerate.
  final int fps;

  /// Whether building for Android platform.
  final bool isAndroid;

  /// Returns the appropriate sink element for the current platform.
  String get _sink => isAndroid
      ? 'glimagesink name=overlay qos=true sync=false max-lateness=20000000'
      : 'appsink name=sink emit-signals=true sync=false';

  /// Android camera chain; forces no AHardwareBuffer/NV12, since devices negotiate different memory types.
  String get _androidGlConvertCamera =>
      'video/x-raw,width=$width,height=$height,framerate=$fps/1 '
      '! videoconvert ! video/x-raw,format=RGBA,width=$width,height=$height '
      '! glupload ! glcolorconvert';

  /// Android videotestsrc chain; its system-memory frames break preroll under AHardwareBuffer caps.
  String get _androidGlConvertTest =>
      'video/x-raw,width=$width,height=$height,framerate=$fps/1 '
      '! glupload ! glcolorconvert';

  /// The pipeline string for [source]; an unknown source gets the ball test pattern.
  String build(String source) {
    return switch (source) {
      'videotestsrc' => _buildTestPattern('ball'),
      'ahcsrc' => _buildAndroidCamera('ahcsrc'),
      'ahc2src' => _buildAndroidCamera('ahc2src'),
      'autovideosrc' => _buildAutoVideoSrc(),
      'avfvideosrc' => _buildAvfVideoSrc(),
      'pattern-smpte' => _buildTestPattern('smpte'),
      'pattern-snow' => _buildTestPattern('snow'),
      _ => _buildTestPattern('ball'),
    };
  }

  String _buildTestPattern(String pattern) {
    if (isAndroid) {
      return 'videotestsrc pattern=$pattern ! $_androidGlConvertTest ! $_sink';
    }
    return 'videotestsrc pattern=$pattern ! '
        'video/x-raw,width=$width,height=$height,framerate=$fps/1 ! $_sink';
  }

  String _buildAndroidCamera(String source) {
    if (isAndroid) {
      return '$source ! $_androidGlConvertCamera ! $_sink';
    }
    return '$source ! $_sink';
  }

  String _buildAutoVideoSrc() {
    if (isAndroid) {
      return 'autovideosrc ! $_androidGlConvertCamera ! $_sink';
    }
    return 'autovideosrc ! $_sink';
  }

  String _buildAvfVideoSrc() {
    return 'avfvideosrc capture-raw-data=true ! videoconvert ! '
        'video/x-raw,format=$kPixelFormat,width=$width,height=$height,'
        'framerate=$fps/1 ! $_sink';
  }
}

// Source fallback policy

/// Video sources per platform, best first; each ends in hardware-free `videotestsrc` rather than a dead texture.
const Map<TargetPlatform, List<String>> kSourceCandidates =
    <TargetPlatform, List<String>>{
      TargetPlatform.android: <String>[
        'ahcsrc',
        'autovideosrc',
        'videotestsrc',
      ],
      TargetPlatform.macOS: <String>['avfvideosrc', 'videotestsrc'],
    };

/// The fallback chain for [platform], or a hardware-free default.
List<String> sourceCandidatesFor(TargetPlatform platform) =>
    kSourceCandidates[platform] ?? const <String>['videotestsrc'];

/// The source after [failed]; `null` when exhausted or off-chain, so a hand-picked pipeline keeps its own error.
String? nextSourceAfter(String failed, List<String> candidates) {
  final int index = candidates.indexOf(failed);
  if (index == -1 || index + 1 >= candidates.length) return null;
  return candidates[index + 1];
}
