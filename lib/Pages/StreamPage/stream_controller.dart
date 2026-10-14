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

  /// Drops the signalling connection and opens a new one; `disconnected`, then `connected`, follow.
  void reconnect();

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
    this.hiddenGrace = const Duration(seconds: 60),
    this.negotiationTimeout = const Duration(seconds: 15),
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

  /// How long the browser tab may be hidden before the session closes; the cat cam encodes per viewer.
  final Duration hiddenGrace;

  /// A session that is not streaming after this rebuilds the signalling connection.
  final Duration negotiationTimeout;

  WebRTCStage _stage = WebRTCStage.connecting;
  String Function(AppLocalizations l10n)? _detail;
  bool _connected = false;
  int _views = 0;
  bool _hidden = false;

  /// The tab stayed hidden past [hiddenGrace], which closed the session; its socket may be dead since.
  bool _closedWhileHidden = false;

  /// Frame counts in a row, one every [WebRTCStreamController.reportFrames] call, that did not move.
  static const int _stalledReports = 5;
  int? _lastFrames;
  int _unchangedReports = 0;
  Timer? _negotiationTimer;
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
    // In a hidden tab the pending close stands: the view shows nobody anything.
    if (!_hidden) {
      _closeTimer?.cancel();
      _closeTimer = null;
    }
    _ensureSession();
  }

  /// The browser hid or showed the tab: hidden for [hiddenGrace], the session closes, and showing it opens one again.
  void pageHidden(bool hidden) {
    if (hidden == _hidden) return;
    _hidden = hidden;
    _closeTimer?.cancel();
    _closeTimer = hidden ? Timer(hiddenGrace, _closeIdleSession) : null;
    if (hidden) return;
    // A sleeping laptop or a changed Wi-Fi leaves a socket that looks open and carries nothing.
    if (_closedWhileHidden) {
      _closedWhileHidden = false;
      _client.reconnect();
      return;
    }
    _ensureSession();
  }

  /// The video's decoded-frame count, which the view reports every 2 s. A count that stops while
  /// streaming is media that died unnoticed, with the camera restarted behind a dead socket.
  void reportFrames(int total) {
    if (_stage != WebRTCStage.streaming || _hidden) {
      _lastFrames = null;
      _unchangedReports = 0;
      return;
    }
    _unchangedReports = total == _lastFrames ? _unchangedReports + 1 : 0;
    _lastFrames = total;
    if (_unchangedReports < _stalledReports) return;
    _lastFrames = null;
    _unchangedReports = 0;
    _closeSession();
    _client.reconnect();
  }

  /// A view shows the stream in a tab the user can see.
  bool get _wanted => _views > 0 && !_hidden;

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
    if (_wanted) return;
    _closedWhileHidden = _hidden;
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
    if (!_wanted || !_connected || _session != null) return;
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
        if (identical(_sessionToken, token)) {
          _negotiationTimer?.cancel();
          _set(WebRTCStage.streaming);
        }
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
    _negotiationTimer?.cancel();
    _negotiationTimer = Timer(negotiationTimeout, () {
      if (!identical(_sessionToken, token)) return;
      // No answer at all: the signalling socket is dead without knowing it, so build a new one.
      _closeSession();
      _client.reconnect();
    });
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
    _negotiationTimer?.cancel();
    _negotiationTimer = null;
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
    _negotiationTimer?.cancel();
    _retryTimer?.cancel();
    _closeSession();
    super.dispose();
  }
}
