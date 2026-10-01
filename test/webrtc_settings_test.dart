// The settings load before the first frame, so a malformed key means a blank page with no UI to say why.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:omni_accelerant/settings/webrtc_settings.dart';

/// The committed asset, inline, so changing it takes a deliberate edit here too.
const String _validJson = '''
{
  "signalingServerUrl": "/webrtc-ws",
  "reconnectionTimeoutMs": 5000,
  "stunServers": ["stun:stun.l.google.com:19302"],
  "turnServers": [],
  "video": {
    "defaultWidth": 1280,
    "defaultHeight": 720,
    "defaultFramerate": 30,
    "defaultBitrateKbps": 2000
  },
  "texture": { "width": 640, "height": 480 },
  "android": { "width": 320, "height": 240, "fps": 15 }
}
''';

Map<String, dynamic> _decode(String source) =>
    json.decode(source) as Map<String, dynamic>;

Map<String, dynamic> _validMap() => _decode(_validJson);

void main() {
  group('a well-formed settings file', () {
    late WebRTCSettings settings;

    setUp(() {
      settings = WebRTCSettings.fromJsonFile(_validMap());
    });

    test('reads every top-level field', () {
      expect(settings.reconnectionTimeoutMs, 5000);
      expect(settings.stunServers, <String>['stun:stun.l.google.com:19302']);
      expect(settings.turnServers, isEmpty);
    });

    test('reads the nested video block', () {
      expect(settings.video.defaultWidth, 1280);
      expect(settings.video.defaultHeight, 720);
      expect(settings.video.defaultFramerate, 30);
      expect(settings.video.defaultBitrateKbps, 2000);
    });

    test('reads the texture geometry the native Stream page uses', () {
      expect(settings.texture.width, 640);
      expect(settings.texture.height, 480);
    });

    test('reads the android geometry', () {
      expect(settings.android.width, 320);
      expect(settings.android.height, 240);
      expect(settings.android.fps, 15);
    });
  });

  group('signalingServerUrl resolution', () {
    // VM only: in Chrome kIsWeb is true and the value resolves against the page's host.
    test('a host-relative value is left alone off the web', () {
      final WebRTCSettings settings = WebRTCSettings.fromJsonFile(_validMap());
      expect(settings.signalingServerUrl, '/webrtc-ws');
    }, testOn: 'vm');

    test('an absolute URL passes through unchanged', () {
      final Map<String, dynamic> map = _validMap();
      map['signalingServerUrl'] = 'wss://cat-cam.local:8443/webrtc-ws';
      expect(
        WebRTCSettings.fromJsonFile(map).signalingServerUrl,
        'wss://cat-cam.local:8443/webrtc-ws',
      );
    });
  });

  group('rejects malformed input by naming the offending key', () {
    test('a missing top-level field', () {
      final Map<String, dynamic> map = _validMap()
        ..remove('reconnectionTimeoutMs');
      expect(
        () => WebRTCSettings.fromJsonFile(map),
        throwsA(
          isA<FormatException>().having(
            (FormatException e) => e.message,
            'message',
            contains('reconnectionTimeoutMs'),
          ),
        ),
      );
    });

    test('a field of the wrong type', () {
      final Map<String, dynamic> map = _validMap();
      map['reconnectionTimeoutMs'] = 'soon';
      expect(
        () => WebRTCSettings.fromJsonFile(map),
        throwsA(isA<FormatException>()),
      );
    });

    test('a missing nested block', () {
      final Map<String, dynamic> map = _validMap()..remove('texture');
      expect(
        () => WebRTCSettings.fromJsonFile(map),
        throwsA(
          isA<FormatException>().having(
            (FormatException e) => e.message,
            'message',
            contains('texture'),
          ),
        ),
      );
    });

    test('a field inside a nested block', () {
      final Map<String, dynamic> map = _validMap();
      (map['android'] as Map<String, dynamic>).remove('fps');
      expect(
        () => WebRTCSettings.fromJsonFile(map),
        throwsA(
          isA<FormatException>().having(
            (FormatException e) => e.message,
            'message',
            contains('fps'),
          ),
        ),
      );
    });

    test('a scalar where a list belongs', () {
      final Map<String, dynamic> map = _validMap();
      map['stunServers'] = 'stun:stun.l.google.com:19302';
      expect(
        () => WebRTCSettings.fromJsonFile(map),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('ICE server lists', () {
    test('an absent list is empty rather than an error', () {
      // A deployment without a TURN server is normal.
      final Map<String, dynamic> map = _validMap()..remove('turnServers');
      expect(WebRTCSettings.fromJsonFile(map).turnServers, isEmpty);
    });

    test('several entries keep their order', () {
      final Map<String, dynamic> map = _validMap();
      map['stunServers'] = <String>['stun:a:1', 'stun:b:2'];
      map['turnServers'] = <String>['turn:c:3'];
      final WebRTCSettings settings = WebRTCSettings.fromJsonFile(map);
      expect(settings.stunServers, <String>['stun:a:1', 'stun:b:2']);
      expect(settings.turnServers, <String>['turn:c:3']);
    });
  });
}
