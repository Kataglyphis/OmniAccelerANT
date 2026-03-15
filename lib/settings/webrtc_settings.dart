/// Video configuration settings for WebRTC streams.
class VideoSettings {
  VideoSettings({
    required this.defaultWidth,
    required this.defaultHeight,
    required this.defaultFramerate,
    required this.defaultBitrateKbps,
  });

  VideoSettings.fromJsonFile(Map<String, dynamic> json)
      : defaultWidth = json['defaultWidth'] as int,
        defaultHeight = json['defaultHeight'] as int,
        defaultFramerate = json['defaultFramerate'] as int,
        defaultBitrateKbps = json['defaultBitrateKbps'] as int;

  final int defaultWidth;
  final int defaultHeight;
  final int defaultFramerate;
  final int defaultBitrateKbps;
}

/// Native texture configuration settings.
class TextureSettings {
  TextureSettings({
    required this.width,
    required this.height,
  });

  TextureSettings.fromJsonFile(Map<String, dynamic> json)
      : width = json['width'] as int,
        height = json['height'] as int;

  final int width;
  final int height;
}

/// Android-specific video configuration settings.
class AndroidSettings {
  AndroidSettings({
    required this.width,
    required this.height,
    required this.fps,
  });

  AndroidSettings.fromJsonFile(Map<String, dynamic> json)
      : width = json['width'] as int,
        height = json['height'] as int,
        fps = json['fps'] as int;

  final int width;
  final int height;
  final int fps;
}

/// WebRTC configuration settings loaded from webrtc_settings.json.
class WebRTCSettings {
  WebRTCSettings({
    required this.signalingServerUrl,
    required this.reconnectionTimeoutMs,
    required this.stunServers,
    required this.turnServers,
    required this.video,
    required this.texture,
    required this.android,
  });

  WebRTCSettings.fromJsonFile(Map<String, dynamic> json)
      : signalingServerUrl = json['signalingServerUrl'] as String,
        reconnectionTimeoutMs = json['reconnectionTimeoutMs'] as int,
        stunServers = (json['stunServers'] as List<dynamic>)
            .map((e) => e.toString())
            .toList(),
        turnServers = (json['turnServers'] as List<dynamic>)
            .map((e) => e.toString())
            .toList(),
        video = VideoSettings.fromJsonFile(
            json['video'] as Map<String, dynamic>),
        texture = TextureSettings.fromJsonFile(
            json['texture'] as Map<String, dynamic>),
        android = AndroidSettings.fromJsonFile(
            json['android'] as Map<String, dynamic>);

  final String signalingServerUrl;
  final int reconnectionTimeoutMs;
  final List<String> stunServers;
  final List<String> turnServers;
  final VideoSettings video;
  final TextureSettings texture;
  final AndroidSettings android;
}
