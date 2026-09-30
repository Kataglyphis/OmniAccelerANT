/// WebRTC and video settings, parsed from `assets/settings/webrtc_settings.json`.
library;

import 'package:flutter/foundation.dart' show kIsWeb;

/// Default resolution, framerate and bitrate of outgoing WebRTC video.
class VideoSettings {
  /// Creates video settings with the specified parameters.
  VideoSettings({
    required this.defaultWidth,
    required this.defaultHeight,
    required this.defaultFramerate,
    required this.defaultBitrateKbps,
  });

  /// Parses [json]; throws [FormatException] on a missing or mistyped field.
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

/// Resolution of the native video texture on desktop and mobile.
class TextureSettings {
  /// Creates texture settings with the specified dimensions.
  TextureSettings({required this.width, required this.height});

  /// Parses [json]; throws [FormatException] on a missing or mistyped field.
  TextureSettings.fromJsonFile(Map<String, dynamic> json)
    : width = _requireInt(json, 'width'),
      height = _requireInt(json, 'height');

  /// Texture width in pixels.
  final int width;

  /// Texture height in pixels.
  final int height;
}

/// Android video settings, separate because devices often need a lower resolution.
class AndroidSettings {
  /// Creates Android settings with the specified parameters.
  AndroidSettings({
    required this.width,
    required this.height,
    required this.fps,
  });

  /// Parses [json]; throws [FormatException] on a missing or mistyped field.
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

/// Signalling, ICE servers and per-platform video settings from `webrtc_settings.json`.
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

  /// Parses [json]; throws [FormatException] on a missing or mistyped field.
  WebRTCSettings.fromJsonFile(Map<String, dynamic> json)
    : signalingServerUrl = _resolveSignalingServerUrl(
        _requireString(json, 'signalingServerUrl'),
      ),
      reconnectionTimeoutMs = _requireInt(json, 'reconnectionTimeoutMs'),
      stunServers = _parseStringList(json, 'stunServers'),
      turnServers = _parseStringList(json, 'turnServers'),
      video = VideoSettings.fromJsonFile(_requireMap(json, 'video')),
      texture = TextureSettings.fromJsonFile(_requireMap(json, 'texture')),
      android = AndroidSettings.fromJsonFile(_requireMap(json, 'android'));

  /// Signalling WebSocket URL; a host-relative `/path` resolves against the page's origin on the web.
  final String signalingServerUrl;

  /// Timeout in milliseconds before attempting to reconnect.
  final int reconnectionTimeoutMs;

  /// STUN server URLs for ICE candidate gathering.
  final List<String> stunServers;

  /// TURN relay URLs; their credentials are configured separately.
  final List<String> turnServers;

  /// Video encoding settings for outgoing streams.
  final VideoSettings video;

  /// Native texture rendering settings for desktop/mobile.
  final TextureSettings texture;

  /// Android-specific video settings.
  final AndroidSettings android;
}

// JSON Parsing Helpers

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

/// Resolves a host-relative URL against the serving page on the web, so no host is baked into the build.
String _resolveSignalingServerUrl(String configured) {
  if (!kIsWeb || !configured.startsWith('/')) {
    return configured;
  }
  final page = Uri.base;
  return Uri(
    scheme: page.scheme == 'https' ? 'wss' : 'ws',
    host: page.host,
    port: page.hasPort ? page.port : null,
    path: configured,
  ).toString();
}
