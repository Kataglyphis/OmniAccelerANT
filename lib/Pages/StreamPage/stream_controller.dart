import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:omni_accelerant/l10n/app_localizations.dart';

/// Where the stream is; the view shows it over the video until [streaming].
enum WebRTCStage {
  /// Waiting for the signalling WebSocket to connect.
  connecting,

  /// Connected to signalling, but no producer to consume yet.
  waitingForProducer,

  /// A consumer session is open and the peer connection is being negotiated.
  negotiating,

  /// Frames are arriving.
  streaming,

  /// The last session failed; [WebRTCStreamController.detail] says why, and a retry follows.
  failed,
}

/// What the signalling server reports; gstwebrtc-api implements it on web, fakes in tests.
abstract class SignallingClient {
  /// Registers the callbacks, once per client, for the page's lifetime.
  void listen({
    required void Function() connected,
    required void Function() disconnected,
    required void Function(String producerId) producerAdded,
    required void Function(String producerId) producerRemoved,
  });

  /// The producers announced so far.
  List<String> availableProducers();

  /// A session on [producerId], or `null` when the client refuses one.
  ConsumerSessionHandle? openSession(
    String producerId, {
    required void Function() streaming,
    required void Function() failed,
  });
}

/// One consumer session, as [SignallingClient.openSession] hands it out.
abstract class ConsumerSessionHandle {
  /// Starts the peer connection; `false` when it could not start.
  bool connect();

  void close();
}

/// The stream's state for the whole page, so a view that remounts finds it as it was.
///
/// A view [attach]es while it shows the stream and [detach]es when it goes. The
/// session outlives the last view for [keepAlive], so a language or theme change
/// keeps the picture; after that the next view opens a new session from the
/// producers the client already knows, without waiting for an event that fired
/// before it existed.
class WebRTCStreamController extends ChangeNotifier {
  WebRTCStreamController(
    this._client, {
    required this.reconnectionTimeoutMs,
    this.producerId,
    this.keepAlive = const Duration(seconds: 30),
    this.retryAfter = const Duration(seconds: 3),
  }) {
    _client.listen(
      connected: _onConnected,
      disconnected: _onDisconnected,
      producerAdded: (_) => _ensureSession(),
      producerRemoved: _onProducerRemoved,
    );
  }

  final SignallingClient _client;

  /// The signalling client's retry interval, for the message after a dropped connection.
  final int reconnectionTimeoutMs;

  /// Consume only this producer; `null` takes the first one announced.
  final String? producerId;

  /// How long a session stays open with no view attached.
  final Duration keepAlive;

  /// How long after a failed session the next one is tried.
  final Duration retryAfter;

  WebRTCStage _stage = WebRTCStage.connecting;
  String Function(AppLocalizations l10n)? _detail;
  bool _connected = false;
  int _views = 0;
  ConsumerSessionHandle? _session;
  String? _sessionProducer;
  Object? _sessionToken;
  Timer? _closeTimer;
  Timer? _retryTimer;

  WebRTCStage get stage => _stage;

  /// The reason behind [stage], localized at render time; `null` means the stage's default.
  String Function(AppLocalizations l10n)? get detail => _detail;

  /// A view shows the stream: it gets the open session, or a new one at once.
  void attach() {
    _views++;
    _closeTimer?.cancel();
    _closeTimer = null;
    _ensureSession();
  }

  /// A view went away; with none left, the session closes after [keepAlive].
  void detach() {
    if (_views == 0) return;
    _views--;
    if (_views == 0) {
      _closeTimer?.cancel();
      _closeTimer = Timer(keepAlive, _closeIdleSession);
    }
  }

  void _closeIdleSession() {
    _closeTimer = null;
    if (_views > 0) return;
    _retryTimer?.cancel();
    _retryTimer = null;
    _closeSession();
    _set(_connected ? WebRTCStage.waitingForProducer : WebRTCStage.connecting);
  }

  void _onConnected() {
    _connected = true;
    if (_stage == WebRTCStage.connecting) _set(WebRTCStage.waitingForProducer);
    _ensureSession();
  }

  void _onDisconnected() {
    _connected = false;
    _retryTimer?.cancel();
    _retryTimer = null;
    _closeSession();
    _set(
      WebRTCStage.connecting,
      (l10n) => l10n.webrtcSignallingLost(reconnectionTimeoutMs),
    );
  }

  void _onProducerRemoved(String id) {
    if (_sessionProducer != id) return;
    _closeSession();
    _set(WebRTCStage.waitingForProducer, (l10n) => l10n.webrtcCameraGone);
    _ensureSession();
  }

  /// Opens a session when a view wants one, the client is connected and none is open.
  void _ensureSession() {
    if (_views == 0 || !_connected || _session != null) return;
    if (_retryTimer != null) return;
    final String? target = _pickProducer();
    if (target == null) {
      if (_stage != WebRTCStage.waitingForProducer) {
        _set(WebRTCStage.waitingForProducer);
      }
      return;
    }
    final Object token = Object();
    _sessionToken = token;
    final ConsumerSessionHandle? session = _client.openSession(
      target,
      streaming: () {
        if (identical(_sessionToken, token)) _set(WebRTCStage.streaming);
      },
      failed: () {
        if (identical(_sessionToken, token)) {
          _failAndRetry((l10n) => l10n.webrtcPeerError);
        }
      },
    );
    if (session == null) {
      _sessionToken = null;
      _failAndRetry((l10n) => l10n.webrtcNoSession(target));
      return;
    }
    _session = session;
    _sessionProducer = target;
    _set(WebRTCStage.negotiating);
    if (!session.connect()) {
      _failAndRetry((l10n) => l10n.webrtcPeerNotStarted);
    }
  }

  String? _pickProducer() {
    final List<String> available = _client.availableProducers();
    final String? wanted = producerId;
    if (wanted != null) return available.contains(wanted) ? wanted : null;
    return available.isEmpty ? null : available.first;
  }

  void _failAndRetry(String Function(AppLocalizations l10n) why) {
    _closeSession();
    _set(WebRTCStage.failed, why);
    _retryTimer?.cancel();
    _retryTimer = Timer(retryAfter, () {
      _retryTimer = null;
      _ensureSession();
    });
  }

  void _closeSession() {
    _sessionToken = null;
    final ConsumerSessionHandle? session = _session;
    _session = null;
    _sessionProducer = null;
    session?.close();
  }

  void _set(
    WebRTCStage stage, [
    String Function(AppLocalizations l10n)? detail,
  ]) {
    if (stage == _stage && detail == null && _detail == null) return;
    _stage = stage;
    _detail = detail;
    notifyListeners();
  }

  @override
  void dispose() {
    _closeTimer?.cancel();
    _retryTimer?.cancel();
    _closeSession();
    super.dispose();
  }
}
