// lib/webrtc_view.dart
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;
import 'package:web/web.dart' as web;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:kataglyphis_inference_engine/js/gstwebrtc_api_interop.dart';

// Add this extension to access the JS property directly.
extension HTMLVideoElementSrcObject on web.HTMLVideoElement {
  external JSAny? get srcObject;
  external set srcObject(JSAny? value);
}

class WebRTCView extends StatefulWidget {
  final String signalingUrl;
  final String? producerIdToConsume;

  const WebRTCView({
    super.key,
    required this.signalingUrl,
    this.producerIdToConsume,
  });

  @override
  State<WebRTCView> createState() => _WebRTCViewState();
}

class _WebRTCViewState extends State<WebRTCView> {
  late final web.HTMLVideoElement _video;
  late final String _viewType;
  late final GstWebRTCAPI _api;
  ConsumerSession? _consumer;

  @override
  void initState() {
    super.initState();

    _video = web.HTMLVideoElement()
      ..autoplay = true
      ..muted =
          true // helps autoplay
      ..controls = true
      ..style.width = '100%'
      ..style.height = '100%'
      ..setAttribute('playsinline', 'true');

    _viewType = 'webrtc-video-${DateTime.now().microsecondsSinceEpoch}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (_) => _video);

    final cfg = GstWebRTCConfig(signalingServerUrl: widget.signalingUrl);
    _api = GstWebRTCAPI(cfg);

    _api.registerConnectionListener(
      ConnectionListener(
        connected: ((JSAny clientId) {
          debugPrint('Connected. ClientId: ${clientId.dartify()}');
          final wanted = widget.producerIdToConsume;
          if (wanted != null && wanted.isNotEmpty) {
            _startConsuming(wanted);
          }
        }).toJS,
        disconnected: (() {
          debugPrint('Disconnected');
        }).toJS,
      ),
    );

    _api.registerPeerListener(
      PeerListener(
        producerAdded: ((JSAny peerAny) {
          final peer = peerAny as Peer;
          debugPrint('Producer added: ${peer.id}');
          if (_consumer == null &&
              (widget.producerIdToConsume == null ||
                  widget.producerIdToConsume == peer.id)) {
            _startConsuming(peer.id);
          }
        }).toJS,
        producerRemoved: ((JSAny peerAny) {
          final peer = peerAny as Peer;
          debugPrint('Producer removed: ${peer.id}');
        }).toJS,
      ),
    );
  }

  @override
  void dispose() {
    _consumer?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }

  void _startConsuming(String producerId) {
    if (_consumer != null) return;

    final consumer = _api.createConsumerSession(producerId);
    if (consumer == null) {
      debugPrint('createConsumerSession returned null (not connected yet?)');
      return;
    }
    _consumer = consumer;

    consumer.addEventListener(
      'streamsChanged'.toJS,
      ((JSAny _) {
        final streams = consumer.streams.toDart; // List<JSAny>
        if (streams.isNotEmpty) {
          final mediaStream = streams.first as web.MediaStream; // cast
          _video.srcObject = mediaStream; // MediaProvider? OK
          _video.play();
        }
      }).toJS,
    );

    consumer.addEventListener(
      'remoteControllerChanged'.toJS,
      ((JSAny _) {
        final rcAny = consumer.remoteController;
        if (rcAny != null) {
          final rc = rcAny as RemoteController;
          rc.attachVideoElement(_video as JSAny);
        }
      }).toJS,
    );

    consumer.addEventListener(
      'stateChanged'.toJS,
      ((JSAny _) {
        debugPrint('Consumer state: ${consumer.state}');
      }).toJS,
    );
    consumer.addEventListener(
      'error'.toJS,
      ((JSAny e) {
        debugPrint('Consumer error event');
      }).toJS,
    );

    final ok = consumer.connect();
    if (!ok) debugPrint('consumer.connect() returned false');
  }
}

extension on JSAny {
  Object? dartify() => switch (this) {
    JSString s => s.toDart,
    JSNumber n => n.toDartInt,
    JSBoolean b => b.toDart,
    _ => toString(),
  };
}
