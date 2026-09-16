// lib/Pages/StreamPage/webrtc_view.dart
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;
import 'package:web/web.dart' as web;
import 'package:flutter/material.dart';

import 'package:omni_accelerant/js/gstwebrtc_api_interop.dart';
import 'package:omni_accelerant/settings/webrtc_settings.dart';

// Add this extension to access the JS property directly.
extension HTMLVideoElementSrcObject on web.HTMLVideoElement {
  external JSAny? get srcObject;
  external set srcObject(JSAny? value);
}

/// What the page is currently doing, in the order it normally happens.
///
/// This exists because every one of these states used to be a `debugPrint` —
/// which is a no-op in a release web build. A visitor whose signalling server
/// was down, or who arrived while no producer was running, got an empty black
/// rectangle and no way to tell the two apart.
enum WebRTCStage {
  /// The signalling socket has not connected yet.
  connecting,

  /// Connected to signalling, but no producer has announced itself.
  waitingForProducer,

  /// A producer was found and the peer connection is being negotiated.
  negotiating,

  /// Media is flowing.
  streaming,

  /// Something failed. [_WebRTCViewState._detail] carries the reason.
  failed,
}

/// Consumes the `cat_webrtc` producer's stream in the web build.
///
/// Web only — the native builds get [WebRTCView] from `webrtc_view_stub.dart`
/// through the conditional import in `stream_page.dart`.
class WebRTCView extends StatefulWidget {
  /// The parsed `assets/settings/webrtc_settings.json`.
  ///
  /// The whole object rather than just the URL, because the ICE servers and the
  /// reconnection timeout in it are part of this widget's job — see
  /// [_buildWebRTCConfig].
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

// ---------------------------------------------------------------------------
// Process-wide singletons
// ---------------------------------------------------------------------------
//
// All three of these outlive any one State object ON PURPOSE.
//
// The app shell rebuilds its `GoRouter` inside `build()`, and its
// `StatefulShellBranch`es are constructed without a `navigatorKey`, so go_router
// mints a fresh `GlobalKey` for each branch on every rebuild. Every theme
// toggle, locale change and accent-colour pick therefore REMOUNTS this widget.
//
// That made the old per-State construction a leak with no ceiling:
//
//   - `GstWebRTCAPI` has no `close()` or `destroy()`. Its constructor ends in
//     `this.connectChannel()`, and its own `closed` handler re-opens the socket
//     on a 2500 ms timer. Constructing one per mount means N live WebSockets to
//     the signalling server, all reconnecting forever, and unregistering the
//     listeners does not stop a single one of them.
//   - `ui_web.platformViewRegistry.registerViewFactory` has no unregister. The
//     old code keyed the view type on `DateTime.now().microsecondsSinceEpoch`,
//     so every mount leaked a factory AND a `<video>` element.
//
// So: construct once, reuse, and make `dispose` responsible only for detaching
// THIS State from the shared objects.

GstWebRTCAPI? _sharedApi;
web.HTMLVideoElement? _sharedVideo;
String? _sharedApiSignalingUrl;

const String _kViewType = 'omni-accelerant-webrtc-video';
bool _viewFactoryRegistered = false;

/// Builds the `RTCPeerConnection` configuration from the app's settings.
///
/// `stunServers` and `turnServers` have been parsed, validated and documented in
/// `webrtc_settings.dart` since it was written, and until 2026-09-16 nothing
/// read them: the old code passed `signalingServerUrl` alone, so the browser
/// fell back to an empty ICE server list. That is survivable on one LAN segment
/// where host candidates reach each other directly, and it is exactly what fails
/// on the setups the README advertises — a phone on Wi-Fi reaching a Pi on
/// Ethernet, or the RISC-V board behind its own firewall.
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

class _WebRTCViewState extends State<WebRTCView> {
  ConsumerSession? _consumer;
  WebRTCStage _stage = WebRTCStage.connecting;
  String? _detail;

  @override
  void initState() {
    super.initState();
    _ensureSharedObjects();
    _attachListeners();
  }

  void _ensureSharedObjects() {
    _sharedVideo ??= web.HTMLVideoElement()
      ..autoplay = true
      ..muted =
          true // helps autoplay
      ..controls = true
      ..style.width = '100%'
      ..style.height = '100%'
      ..setAttribute('playsinline', 'true');

    if (!_viewFactoryRegistered) {
      ui_web.platformViewRegistry.registerViewFactory(
        _kViewType,
        (_) => _sharedVideo!,
      );
      _viewFactoryRegistered = true;
    }

    final String url = widget.settings.signalingServerUrl;
    if (_sharedApi == null) {
      _sharedApi = GstWebRTCAPI(
        GstWebRTCConfig(
          signalingServerUrl: url,
          reconnectionTimeout: widget.settings.reconnectionTimeoutMs,
          webrtcConfig: _buildWebRTCConfig(widget.settings),
        ),
      );
      _sharedApiSignalingUrl = url;
    } else if (_sharedApiSignalingUrl != url) {
      // Settings are loaded once before the first frame, so this cannot happen
      // today. It is worth a loud line rather than a silent wrong answer if
      // that ever stops being true: the API has no way to re-target its socket.
      debugPrint(
        'WebRTCView: signalling URL changed from $_sharedApiSignalingUrl to '
        '$url, but GstWebRTCAPI cannot be re-targeted. Reload the page.',
      );
    }
  }

  void _attachListeners() {
    final GstWebRTCAPI api = _sharedApi!;

    // A remount re-registers; clearing first is what stops the previous State's
    // closures (which capture a dead `this`) from staying live.
    api.unregisterAllConnectionListeners();
    api.unregisterAllPeerListeners();

    api.registerConnectionListener(
      ConnectionListener(
        connected: ((JSAny clientId) {
          debugPrint('Connected. ClientId: ${clientId.dartify()}');
          _setStage(WebRTCStage.waitingForProducer);
          final String? wanted = widget.producerIdToConsume;
          if (wanted != null && wanted.isNotEmpty) {
            _startConsuming(wanted);
          }
        }).toJS,
        disconnected: (() {
          debugPrint('Disconnected');
          _consumer = null;
          _setStage(
            WebRTCStage.connecting,
            'Lost the signalling connection — retrying every '
            '${widget.settings.reconnectionTimeoutMs} ms.',
          );
        }).toJS,
      ),
    );

    api.registerPeerListener(
      PeerListener(
        producerAdded: ((JSAny peerAny) {
          final Peer peer = peerAny as Peer;
          debugPrint('Producer added: ${peer.id}');
          if (_consumer == null &&
              (widget.producerIdToConsume == null ||
                  widget.producerIdToConsume == peer.id)) {
            _startConsuming(peer.id);
          }
        }).toJS,
        producerRemoved: ((JSAny peerAny) {
          final Peer peer = peerAny as Peer;
          debugPrint('Producer removed: ${peer.id}');
          // Dropping the reference is what lets the NEXT producerAdded start a
          // session. Without it `_startConsuming`'s `_consumer != null` guard
          // wedged the page until a manual reload every time the producer was
          // restarted — which is most of a bring-up session.
          _consumer?.close();
          _consumer = null;
          _sharedVideo?.srcObject = null;
          _setStage(WebRTCStage.waitingForProducer, 'The producer went away.');
        }).toJS,
      ),
    );
  }

  void _setStage(WebRTCStage stage, [String? detail]) {
    if (!mounted) return;
    setState(() {
      _stage = stage;
      _detail = detail;
    });
  }

  @override
  void dispose() {
    // Detach this State from the shared API. The socket deliberately stays
    // open: it is shared, it reconnects itself, and there is no close() to call.
    _sharedApi
      ?..unregisterAllConnectionListeners()
      ..unregisterAllPeerListeners();
    _consumer?.close();
    _consumer = null;
    super.dispose();
  }

  void _startConsuming(String producerId) {
    if (_consumer != null) return;

    final ConsumerSession? consumer = _sharedApi!.createConsumerSession(
      producerId,
    );
    if (consumer == null) {
      debugPrint('createConsumerSession returned null (not connected yet?)');
      _setStage(
        WebRTCStage.failed,
        'Could not open a session for producer $producerId.',
      );
      return;
    }
    _consumer = consumer;
    _setStage(WebRTCStage.negotiating);

    consumer.addEventListener(
      'streamsChanged'.toJS,
      ((JSAny _) {
        final List<JSAny> streams = consumer.streams.toDart;
        if (streams.isNotEmpty) {
          final web.MediaStream mediaStream = streams.first as web.MediaStream;
          _sharedVideo?.srcObject = mediaStream;
          _sharedVideo?.play();
          _setStage(WebRTCStage.streaming);
        }
      }).toJS,
    );

    consumer.addEventListener(
      'remoteControllerChanged'.toJS,
      ((JSAny _) {
        final JSObject? rcAny = consumer.remoteController;
        if (rcAny != null) {
          final RemoteController rc = rcAny as RemoteController;
          rc.attachVideoElement(_sharedVideo as JSAny?);
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
        _setStage(
          WebRTCStage.failed,
          'The peer connection reported an error. If this is a remote board, '
          'check that the WebRTC UDP range reaches it.',
        );
      }).toJS,
    );

    final bool ok = consumer.connect();
    if (!ok) {
      debugPrint('consumer.connect() returned false');
      _setStage(WebRTCStage.failed, 'Could not start the peer connection.');
    }
  }

  // -------------------------------------------------------------------------
  // Rendering
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: <Widget>[
        const HtmlElementView(viewType: _kViewType),
        if (_stage != WebRTCStage.streaming) _buildStatusOverlay(context),
      ],
    );
  }

  Widget _buildStatusOverlay(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool failed = _stage == WebRTCStage.failed;

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
                  _headline,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: failed ? theme.colorScheme.error : null,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _detail ?? _defaultDetail,
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

  String get _headline => switch (_stage) {
    WebRTCStage.connecting => 'Connecting to the signalling server',
    WebRTCStage.waitingForProducer => 'Waiting for a camera',
    WebRTCStage.negotiating => 'Negotiating the video stream',
    WebRTCStage.streaming => 'Streaming',
    WebRTCStage.failed => 'The stream could not be started',
  };

  /// The fallback second line.
  ///
  /// Each one names the thing the visitor (or the person bringing a board up)
  /// would check next, rather than restating the headline.
  String get _defaultDetail => switch (_stage) {
    WebRTCStage.connecting => widget.settings.signalingServerUrl,
    WebRTCStage.waitingForProducer =>
      'Signalling is up, but no producer has announced itself. Start '
          'kataglyphis_cat_webrtc on the camera host.',
    WebRTCStage.negotiating => 'Exchanging ICE candidates.',
    WebRTCStage.streaming => '',
    WebRTCStage.failed => 'See the browser console for the underlying error.',
  };
}
