/// WebRTC and video streaming configuration settings.
///
/// This library provides configuration classes for WebRTC signaling,
/// video encoding, and platform-specific texture rendering settings.
/// Settings are typically loaded from `assets/settings/webrtc_settings.json`.
library;

/// Video encoding configuration settings for WebRTC streams.
///
/// These settings control the default resolution, framerate, and bitrate
/// for outgoing video streams.
///
/// Example JSON:
/// ```json
/// {
///   "defaultWidth": 1280,
///   "defaultHeight": 720,
///   "defaultFramerate": 30,
///   "defaultBitrateKbps": 2000
/// }
/// ```
class VideoSettings {
  /// Creates video settings with the specified parameters.
  VideoSettings({
    required this.defaultWidth,
    required this.defaultHeight,
    required this.defaultFramerate,
    required this.defaultBitrateKbps,
  });

  /// Creates video settings from a JSON map.
  ///
  /// Throws [TypeError] if required fields are missing or have wrong types.
  VideoSettings.fromJsonFile(Map<String, dynamic> json)
    : defaultWidth = _requireInt(json, 'defaultWidth'),
      defaultHeight = _requireInt(json, 'defaultHeight'),
      defaultFramerate = _requireInt(json, 'defaultFramerate'),
      defaultBitrateKbps = _requireInt(json, 'defaultBitrateKbps');

  /// Default video width in pixels.
  final int defaultWidth;

  /// Default video height in pixels.
  final int defaultHeight;

  /// Default framerate in frames per second.
  final int defaultFramerate;

  /// Default bitrate in kilobits per second.
  final int defaultBitrateKbps;
}

/// Native texture rendering configuration settings.
///
/// These settings control the resolution of the native texture
/// used for video rendering on desktop and mobile platforms.
///
/// Example JSON:
/// ```json
/// {
///   "width": 640,
///   "height": 480
/// }
/// ```
class TextureSettings {
  /// Creates texture settings with the specified dimensions.
  TextureSettings({required this.width, required this.height});

  /// Creates texture settings from a JSON map.
  ///
  /// Throws [TypeError] if required fields are missing or have wrong types.
  TextureSettings.fromJsonFile(Map<String, dynamic> json)
    : width = _requireInt(json, 'width'),
      height = _requireInt(json, 'height');

  /// Texture width in pixels.
  final int width;

  /// Texture height in pixels.
  final int height;
}

/// Android-specific video configuration settings.
///
/// Android devices often have different performance characteristics
/// and may require lower resolutions for smooth rendering.
///
/// Example JSON:
/// ```json
/// {
///   "width": 320,
///   "height": 240,
///   "fps": 15
/// }
/// ```
class AndroidSettings {
  /// Creates Android settings with the specified parameters.
  AndroidSettings({
    required this.width,
    required this.height,
    required this.fps,
  });

  /// Creates Android settings from a JSON map.
  ///
  /// Throws [TypeError] if required fields are missing or have wrong types.
  AndroidSettings.fromJsonFile(Map<String, dynamic> json)
    : width = _requireInt(json, 'width'),
      height = _requireInt(json, 'height'),
      fps = _requireInt(json, 'fps');

  /// Video width in pixels for Android.
  final int width;

  /// Video height in pixels for Android.
  final int height;

  /// Target framerate for Android in frames per second.
  final int fps;
}

/// WebRTC configuration settings loaded from webrtc_settings.json.
///
/// This class contains all configuration needed for WebRTC signaling,
/// ICE server configuration, and platform-specific video settings.
///
/// Example JSON:
/// ```json
/// {
///   "signalingServerUrl": "wss://example.com:8443",
///   "reconnectionTimeoutMs": 5000,
///   "stunServers": ["stun:stun.l.google.com:19302"],
///   "turnServers": [],
///   "video": { ... },
///   "texture": { ... },
///   "android": { ... }
/// }
/// ```
///
/// See also:
/// - [VideoSettings] for video encoding configuration
/// - [TextureSettings] for native texture rendering configuration
/// - [AndroidSettings] for Android-specific settings
class WebRTCSettings {
  /// Creates WebRTC settings with all required parameters.
  WebRTCSettings({
    required this.signalingServerUrl,
    required this.reconnectionTimeoutMs,
    required this.stunServers,
    required this.turnServers,
    required this.video,
    required this.texture,
    required this.android,
  });

  /// Creates WebRTC settings from a JSON map.
  ///
  /// Throws [FormatException] if required fields are missing or have wrong types.
  WebRTCSettings.fromJsonFile(Map<String, dynamic> json)
    : signalingServerUrl = _requireString(json, 'signalingServerUrl'),
      reconnectionTimeoutMs = _requireInt(json, 'reconnectionTimeoutMs'),
      stunServers = _parseStringList(json, 'stunServers'),
      turnServers = _parseStringList(json, 'turnServers'),
      video = VideoSettings.fromJsonFile(_requireMap(json, 'video')),
      texture = TextureSettings.fromJsonFile(_requireMap(json, 'texture')),
      android = AndroidSettings.fromJsonFile(_requireMap(json, 'android'));

  /// The WebSocket URL for the signaling server.
  ///
  /// Should use `wss://` for secure connections in production.
  final String signalingServerUrl;

  /// Timeout in milliseconds before attempting to reconnect.
  final int reconnectionTimeoutMs;

  /// List of STUN server URLs for ICE candidate gathering.
  ///
  /// Example: `["stun:stun.l.google.com:19302"]`
  final List<String> stunServers;

  /// List of TURN server URLs for relay when direct connection fails.
  ///
  /// TURN servers require authentication credentials which should be
  /// configured separately.
  final List<String> turnServers;

  /// Video encoding settings for outgoing streams.
  final VideoSettings video;

  /// Native texture rendering settings for desktop/mobile.
  final TextureSettings texture;

  /// Android-specific video settings.
  final AndroidSettings android;
}

// ============================================================================
// JSON Parsing Helpers
// ============================================================================

/// Safely extracts a required string field from JSON.
String _requireString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) {
    throw FormatException('Missing required field: $key');
  }
  if (value is! String) {
    throw FormatException(
      'Field "$key" must be a String, got ${value.runtimeType}',
    );
  }
  return value;
}

/// Safely extracts a required int field from JSON.
int _requireInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) {
    throw FormatException('Missing required field: $key');
  }
  if (value is! int) {
    throw FormatException(
      'Field "$key" must be an int, got ${value.runtimeType}',
    );
  }
  return value;
}

/// Safely extracts a required nested map field from JSON.
Map<String, dynamic> _requireMap(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) {
    throw FormatException('Missing required field: $key');
  }
  if (value is! Map<String, dynamic>) {
    throw FormatException(
      'Field "$key" must be a Map, got ${value.runtimeType}',
    );
  }
  return value;
}

/// Parses a list of strings from JSON with validation.
List<String> _parseStringList(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return [];
  if (value is! List) {
    throw FormatException(
      'Field "$key" must be a List, got ${value.runtimeType}',
    );
  }
  return value.map((e) => e.toString()).toList();
}
