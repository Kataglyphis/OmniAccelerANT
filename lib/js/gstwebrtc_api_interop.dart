// lib/js/gstwebrtc_api_interop.dart
@JS()
library gstwebrtc_api_interop;

import 'dart:js_interop';

@JS('GstWebRTCAPI')
@staticInterop
class GstWebRTCAPI {
  external factory GstWebRTCAPI([GstWebRTCConfig? userConfig]);
}

extension GstWebRTCAPIMembers on GstWebRTCAPI {
  external bool registerConnectionListener(ConnectionListener listener);
  external bool registerPeerListener(PeerListener listener);

  external ConsumerSession? createConsumerSession(String producerId);
  external ConsumerSession? createConsumerSessionWithOfferOptions(
    String producerId,
    JSAny offerOptions,
  );

  external JSArray<JSObject> getAvailableProducers();
  external JSArray<JSObject> getAvailableConsumers();

  external void unregisterAllConnectionListeners();
  external void unregisterAllPeerListeners();
}

@JS()
@staticInterop
@anonymous
class GstWebRTCConfig {
  external factory GstWebRTCConfig({
    JSAny? meta,
    String? signalingServerUrl,
    int? reconnectionTimeout,
    JSAny? webrtcConfig,
  });
}

@JS()
@staticInterop
@anonymous
class ConnectionListener {
  external factory ConnectionListener({
    JSFunction? connected,
    JSFunction? disconnected,
  });
}

@JS()
@staticInterop
@anonymous
class PeerListener {
  external factory PeerListener({
    JSFunction? producerAdded,
    JSFunction? producerRemoved,
    JSFunction? consumerAdded,
    JSFunction? consumerRemoved,
  });
}

@JS()
@staticInterop
@anonymous
class Peer {
  external factory Peer({String id, JSAny meta});
}

extension PeerMembers on Peer {
  external String get id;
  external JSAny get meta;
}

@JS()
@staticInterop
class ConsumerSession {}

extension ConsumerSessionMembers on ConsumerSession {
  external bool connect();
  external void close();
  external void addEventListener(JSString type, JSFunction callback);
  external JSArray<JSAny> get streams;
  external JSObject? get remoteController;
  external set mungeStereoHack(bool enable);
  external int get state;
}

@JS()
@staticInterop
class RemoteController {}

extension RemoteControllerMembers on RemoteController {
  external void addEventListener(JSString type, JSFunction callback);
  external void attachVideoElement(JSAny? element);
  external void close();
}
