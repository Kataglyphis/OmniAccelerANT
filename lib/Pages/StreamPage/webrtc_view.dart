import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:web/web.dart' as web;
import 'package:flutter/material.dart';

import 'package:omni_accelerant/js/gstwebrtc_api_interop.dart';
import 'package:omni_accelerant/l10n/app_localizations.dart';
import 'package:omni_accelerant/Pages/StreamPage/stream_controller.dart';
import 'package:omni_accelerant/settings/webrtc_settings.dart';

/// Consumes the `cat_webrtc` producer's stream; web only, native builds get the stub.
class WebRTCView extends StatefulWidget {
  /// The parsed `assets/settings/webrtc_settings.json`, whole for its ICE servers and reconnection timeout.
  final WebRTCSettings settings;

  /// Consume only this producer id. `null` takes the first one announced.
  final String? producerIdToConsume;

  const WebRTCView({
    super.key,
    required this.settings,
    this.producerIdToConsume,
  });

  @override
  State<WebRTCView> createState() => _WebRTCViewState();
}

// Process-wide on purpose: a page, theme or locale change remounts this widget, and the stream must not notice.

web.HTMLVideoElement? _sharedVideo;
WebRTCStreamController? _sharedController;
String? _sharedSignalingUrl;

const String _kViewType = 'omni-accelerant-webrtc-video';
bool _viewFactoryRegistered = false;

/// The `RTCPeerConnection` config; without ICE servers nothing beyond one LAN segment connects.
JSAny? _buildWebRTCConfig(WebRTCSettings settings) {
  final List<Map<String, Object?>> iceServers = <Map<String, Object?>>[
    for (final String url in settings.stunServers)
      <String, Object?>{'urls': url},
    for (final String url in settings.turnServers)
      <String, Object?>{'urls': url},
  ];
  if (iceServers.isEmpty) return null;
  return <String, Object?>{'iceServers': iceServers}.jsify();
}

/// The page's one video element, view factory and stream controller, made by the first view.
WebRTCStreamController _ensureSharedObjects(WebRTCView widget) {
  final web.HTMLVideoElement video = _sharedVideo ??= web.HTMLVideoElement()
    ..autoplay = true
    ..muted =
        true // helps autoplay
    ..controls = true
    ..style.width = '100%'
    ..style.height = '100%'
    ..setAttribute('playsinline', 'true');

  if (!_viewFactoryRegistered) {
    ui_web.platformViewRegistry.registerViewFactory(_kViewType, (_) => video);
    _viewFactoryRegistered = true;
  }

  final String url = widget.settings.signalingServerUrl;
  final WebRTCStreamController? existing = _sharedController;
  if (existing != null) {
    if (_sharedSignalingUrl != url) {
      // The API cannot re-target its socket, so say so rather than answer wrong.
      debugPrint(
        'WebRTCView: signalling URL changed from $_sharedSignalingUrl to '
        '$url, but GstWebRTCAPI cannot be re-targeted. Reload the page.',
      );
    }
    return existing;
  }
  final GstWebRTCAPI api = GstWebRTCAPI(
    GstWebRTCConfig(
      signalingServerUrl: url,
      reconnectionTimeout: widget.settings.reconnectionTimeoutMs,
      webrtcConfig: _buildWebRTCConfig(widget.settings),
    ),
  );
  _sharedSignalingUrl = url;
  return _sharedController = WebRTCStreamController(
    _GstSignallingClient(api, video),
    reconnectionTimeoutMs: widget.settings.reconnectionTimeoutMs,
    producerId: widget.producerIdToConsume,
  );
}

/// gstwebrtc-api behind [SignallingClient]; a session's media goes into the shared video element.
class _GstSignallingClient implements SignallingClient {
  _GstSignallingClient(this._api, this._video);

  final GstWebRTCAPI _api;
  final web.HTMLVideoElement _video;

  @override
  void listen({
    required void Function() connected,
    required void Function() disconnected,
    required void Function(String producerId) producerAdded,
    required void Function(String producerId) producerRemoved,
  }) {
    _api.registerConnectionListener(
      ConnectionListener(
        connected: ((JSAny clientId) {
          debugPrint('Connected. ClientId: ${clientId.dartify()}');
          connected();
        }).toJS,
        disconnected: (() {
          debugPrint('Disconnected');
          disconnected();
        }).toJS,
      ),
    );
    _api.registerPeerListener(
      PeerListener(
        producerAdded: ((JSAny peerAny) {
          final Peer peer = peerAny as Peer;
          debugPrint('Producer added: ${peer.id}');
          producerAdded(peer.id);
        }).toJS,
        producerRemoved: ((JSAny peerAny) {
          final Peer peer = peerAny as Peer;
          debugPrint('Producer removed: ${peer.id}');
          producerRemoved(peer.id);
        }).toJS,
      ),
    );
  }

  @override
  List<String> availableProducers() => <String>[
    for (final JSObject peer in _api.getAvailableProducers().toDart)
      (peer as Peer).id,
  ];

  @override
  ConsumerSessionHandle? openSession(
    String producerId, {
    required void Function() streaming,
    required void Function() failed,
  }) {
    final ConsumerSession? session = _api.createConsumerSession(producerId);
    if (session == null) {
      debugPrint('createConsumerSession($producerId) returned null');
      return null;
    }
    session.addEventListener(
      'streamsChanged'.toJS,
      ((JSAny _) {
        final List<JSAny> streams = session.streams.toDart;
        if (streams.isEmpty) return;
        _video.srcObject = streams.first as web.MediaStream;
        _video.play();
        streaming();
      }).toJS,
    );
    session.addEventListener(
      'remoteControllerChanged'.toJS,
      ((JSAny _) {
        final JSObject? controller = session.remoteController;
        if (controller != null) {
          (controller as RemoteController).attachVideoElement(_video as JSAny?);
        }
      }).toJS,
    );
    session.addEventListener(
      'stateChanged'.toJS,
      ((JSAny _) {
        debugPrint('Consumer state: ${session.state}');
      }).toJS,
    );
    session.addEventListener(
      'error'.toJS,
      ((JSAny _) {
        debugPrint('Consumer error event');
        failed();
      }).toJS,
    );
    return _GstSession(session, _video);
  }
}

class _GstSession implements ConsumerSessionHandle {
  _GstSession(this._session, this._video);

  final ConsumerSession _session;
  final web.HTMLVideoElement _video;

  @override
  bool connect() => _session.connect();

  @override
  void close() {
    _session.close();
    _video.srcObject = null;
  }
}

class _WebRTCViewState extends State<WebRTCView> {
  late final WebRTCStreamController _controller;
  final List<Timer> _resumeTimers = <Timer>[];

  @override
  void initState() {
    super.initState();
    _controller = _ensureSharedObjects(widget);
    _controller.addListener(_onStage);
    _controller.attach();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resumeAfterRemount());
  }

  /// A remount moves the shared element, and the browser pauses a media element that left the document a little later.
  void _resumeAfterRemount() {
    for (final int ms in const <int>[0, 300, 1000, 2000, 4000]) {
      _resumeTimers.add(Timer(Duration(milliseconds: ms), _resumeVideo));
    }
  }

  void _onStage() {
    if (mounted) setState(() {});
  }

  void _resumeVideo() {
    final web.HTMLVideoElement? video = _sharedVideo;
    if (video != null &&
        video.srcObject != null &&
        video.isConnected &&
        video.paused) {
      video.play();
    }
  }

  @override
  void dispose() {
    for (final Timer timer in _resumeTimers) {
      timer.cancel();
    }
    _controller.removeListener(_onStage);
    _controller.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final WebRTCStage stage = _controller.stage;
    return Stack(
      fit: StackFit.passthrough,
      children: <Widget>[
        const HtmlElementView(viewType: _kViewType),
        if (stage != WebRTCStage.streaming) _buildStatusOverlay(context, stage),
      ],
    );
  }

  Widget _buildStatusOverlay(BuildContext context, WebRTCStage stage) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final bool failed = stage == WebRTCStage.failed;

    return Positioned.fill(
      child: ColoredBox(
        color: theme.colorScheme.surface.withValues(alpha: 0.85),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (failed)
                  Icon(
                    Icons.error_outline,
                    color: theme.colorScheme.error,
                    size: 32,
                  )
                else
                  const SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                const SizedBox(height: 12),
                Text(
                  _headline(l10n, stage),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: failed ? theme.colorScheme.error : null,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _controller.detail?.call(l10n) ?? _defaultDetail(l10n, stage),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _headline(AppLocalizations l10n, WebRTCStage stage) => switch (stage) {
    WebRTCStage.connecting => l10n.webrtcConnecting,
    WebRTCStage.waitingForProducer => l10n.webrtcWaitingForCamera,
    WebRTCStage.negotiating => l10n.webrtcNegotiating,
    WebRTCStage.streaming => l10n.webrtcStreaming,
    WebRTCStage.failed => l10n.webrtcFailed,
  };

  /// The fallback second line: what to check next, not the headline again.
  String _defaultDetail(AppLocalizations l10n, WebRTCStage stage) =>
      switch (stage) {
        WebRTCStage.connecting => widget.settings.signalingServerUrl,
        WebRTCStage.waitingForProducer => l10n.webrtcNoCamera,
        WebRTCStage.negotiating => l10n.webrtcExchangingCandidates,
        WebRTCStage.streaming => '',
        WebRTCStage.failed => l10n.webrtcSeeConsole,
      };
}
