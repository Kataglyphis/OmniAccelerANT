import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_accelerant/Pages/StreamPage/stream_controller.dart';
import 'package:omni_accelerant/l10n/app_localizations.dart';

class _FakeSession implements ConsumerSessionHandle {
  _FakeSession(this.producerId, this.streaming, this.failed);

  final String producerId;
  final void Function() streaming;
  final void Function() failed;
  bool connected = false;
  bool closed = false;

  @override
  bool connect() => connected = true;

  @override
  void close() => closed = true;
}

/// Stands in for gstwebrtc-api, which never replays a `connected` or `producerAdded` that already happened.
class _FakeClient implements SignallingClient {
  late void Function() connected;
  late void Function() disconnected;
  late void Function(String producerId) _producerAdded;
  late void Function(String producerId) _producerRemoved;
  int listens = 0;
  final List<String> producers = <String>[];
  final List<_FakeSession> sessions = <_FakeSession>[];

  @override
  void listen({
    required void Function() connected,
    required void Function() disconnected,
    required void Function(String producerId) producerAdded,
    required void Function(String producerId) producerRemoved,
  }) {
    listens++;
    this.connected = connected;
    this.disconnected = disconnected;
    _producerAdded = producerAdded;
    _producerRemoved = producerRemoved;
  }

  @override
  List<String> availableProducers() => List<String>.of(producers);

  int reconnects = 0;

  /// As gstwebrtc-api does: the old channel's end is announced at once, the new one's start later.
  @override
  void reconnect() {
    reconnects++;
    disconnected();
  }

  @override
  ConsumerSessionHandle? openSession(
    String producerId, {
    required void Function() streaming,
    required void Function() failed,
  }) {
    final _FakeSession session = _FakeSession(producerId, streaming, failed);
    sessions.add(session);
    return session;
  }

  void announce(String id) {
    producers.add(id);
    _producerAdded(id);
  }

  void withdraw(String id) {
    producers.remove(id);
    _producerRemoved(id);
  }
}

/// A controller with one view attached and the camera streaming, the state a visitor sees.
(WebRTCStreamController, _FakeClient) _streaming() {
  final _FakeClient client = _FakeClient();
  final WebRTCStreamController controller = WebRTCStreamController(
    client,
    reconnectionTimeoutMs: 5000,
  );
  controller.attach();
  client.connected();
  client.announce('cam');
  client.sessions.single.streaming();
  expect(controller.stage, WebRTCStage.streaming);
  return (controller, client);
}

void main() {
  test(
    'a first view streams once signalling connects and a camera is announced',
    () {
      final _FakeClient client = _FakeClient();
      final WebRTCStreamController controller = WebRTCStreamController(
        client,
        reconnectionTimeoutMs: 5000,
      );
      controller.attach();
      expect(controller.stage, WebRTCStage.connecting);
      client.connected();
      expect(controller.stage, WebRTCStage.waitingForProducer);
      client.announce('cam');
      expect(controller.stage, WebRTCStage.negotiating);
      expect(client.sessions.single.connected, isTrue);
      client.sessions.single.streaming();
      expect(controller.stage, WebRTCStage.streaming);
      controller.dispose();
    },
  );

  test('a remount, as a language or theme change makes, keeps the session', () {
    final (WebRTCStreamController controller, _FakeClient client) =
        _streaming();
    // Flutter mounts the new view before it disposes the old one.
    controller.attach();
    controller.detach();
    expect(controller.stage, WebRTCStage.streaming);
    expect(client.sessions, hasLength(1));
    expect(client.sessions.single.closed, isFalse);
    controller.dispose();
  });

  testWidgets('a page change shorter than the keep-alive keeps the session', (
    WidgetTester tester,
  ) async {
    final (WebRTCStreamController controller, _FakeClient client) =
        _streaming();
    controller.detach();
    await tester.pump(const Duration(seconds: 20));
    controller.attach();
    await tester.pump(const Duration(seconds: 60));
    expect(controller.stage, WebRTCStage.streaming);
    expect(client.sessions, hasLength(1));
    expect(client.sessions.single.closed, isFalse);
    controller.dispose();
  });

  testWidgets(
    'after a longer absence the next view opens a session at once, with no new event',
    (WidgetTester tester) async {
      final (WebRTCStreamController controller, _FakeClient client) =
          _streaming();
      controller.detach();
      await tester.pump(const Duration(seconds: 31));
      expect(client.sessions.single.closed, isTrue);
      expect(controller.stage, WebRTCStage.waitingForProducer);

      // The socket connected and the camera was announced long ago; no event repeats that.
      controller.attach();
      expect(controller.stage, WebRTCStage.negotiating);
      expect(client.sessions, hasLength(2));
      client.sessions.last.streaming();
      expect(controller.stage, WebRTCStage.streaming);
      controller.dispose();
    },
  );

  test('a restarted camera is consumed again', () {
    final (WebRTCStreamController controller, _FakeClient client) =
        _streaming();
    client.withdraw('cam');
    expect(client.sessions.first.closed, isTrue);
    expect(controller.stage, WebRTCStage.waitingForProducer);
    final AppLocalizations l10n = lookupAppLocalizations(const Locale('en'));
    expect(controller.detail?.call(l10n), 'The camera went offline.');
    client.announce('cam');
    expect(client.sessions, hasLength(2));
    expect(controller.stage, WebRTCStage.negotiating);
    controller.dispose();
  });

  test(
    'lost signalling shows connecting, and its return resumes the stream',
    () {
      final (WebRTCStreamController controller, _FakeClient client) =
          _streaming();
      client.producers.clear();
      client.disconnected();
      expect(controller.stage, WebRTCStage.connecting);
      expect(client.sessions.single.closed, isTrue);
      final AppLocalizations l10n = lookupAppLocalizations(const Locale('en'));
      expect(
        controller.detail?.call(l10n),
        'Lost the signalling connection — retrying every 5000 ms.',
      );
      client.connected();
      expect(controller.stage, WebRTCStage.waitingForProducer);
      client.announce('cam');
      client.sessions.last.streaming();
      expect(controller.stage, WebRTCStage.streaming);
      expect(client.sessions, hasLength(2));
      controller.dispose();
    },
  );

  testWidgets('a failed session is retried after a pause', (
    WidgetTester tester,
  ) async {
    final (WebRTCStreamController controller, _FakeClient client) =
        _streaming();
    client.sessions.single.failed();
    expect(controller.stage, WebRTCStage.failed);
    expect(client.sessions.single.closed, isTrue);
    // A late event from the closed session changes nothing.
    client.sessions.single.streaming();
    expect(controller.stage, WebRTCStage.failed);
    await tester.pump(const Duration(seconds: 3));
    expect(client.sessions, hasLength(2));
    expect(controller.stage, WebRTCStage.negotiating);
    controller.dispose();
  });

  test('the client is listened to once, however often views come and go', () {
    final (WebRTCStreamController controller, _FakeClient client) =
        _streaming();
    for (int i = 0; i < 5; i++) {
      controller.attach();
      controller.detach();
    }
    expect(client.listens, 1);
    expect(client.sessions, hasLength(1));
    controller.dispose();
  });

  test('a fixed producer id waits for that producer only', () {
    final _FakeClient client = _FakeClient();
    final WebRTCStreamController controller = WebRTCStreamController(
      client,
      reconnectionTimeoutMs: 5000,
      producerId: 'garden',
    );
    controller.attach();
    client.connected();
    client.announce('kitchen');
    expect(client.sessions, isEmpty);
    expect(controller.stage, WebRTCStage.waitingForProducer);
    client.announce('garden');
    expect(client.sessions.single.producerId, 'garden');
    controller.dispose();
  });

  testWidgets(
    'a tab hidden for a minute closes the session, and showing it opens one',
    (WidgetTester tester) async {
      final (WebRTCStreamController controller, _FakeClient client) =
          _streaming();
      // A glance at another tab keeps the picture.
      controller.pageHidden(true);
      await tester.pump(const Duration(seconds: 30));
      controller.pageHidden(false);
      await tester.pump(const Duration(seconds: 60));
      expect(client.sessions.single.closed, isFalse);
      // A minute away closes it, so the cat cam stops encoding for nobody.
      controller.pageHidden(true);
      await tester.pump(const Duration(seconds: 61));
      expect(client.sessions.single.closed, isTrue);
      expect(controller.stage, WebRTCStage.waitingForProducer);
      // A view that mounts while the tab is hidden opens nothing either.
      controller.attach();
      expect(client.sessions, hasLength(1));
      controller.detach();
      // Back after so long, it first rebuilds the signalling connection, then opens the session on it.
      controller.pageHidden(false);
      expect(client.reconnects, 1);
      client.connected();
      expect(client.sessions, hasLength(2));
      expect(controller.stage, WebRTCStage.negotiating);
      controller.dispose();
    },
  );

  testWidgets('a view attached while hidden does not keep the session open', (
    WidgetTester tester,
  ) async {
    final (WebRTCStreamController controller, _FakeClient client) =
        _streaming();
    controller.pageHidden(true);
    await tester.pump(const Duration(seconds: 10));
    // A remount in the hidden tab, as a theme change from the system makes.
    controller.attach();
    controller.detach();
    await tester.pump(const Duration(seconds: 55));
    expect(client.sessions.single.closed, isTrue);
    controller.dispose();
  });

  testWidgets(
    'a session that gets no answer rebuilds the signalling connection',
    (WidgetTester tester) async {
      final _FakeClient client = _FakeClient();
      final WebRTCStreamController controller = WebRTCStreamController(
        client,
        reconnectionTimeoutMs: 5000,
      );
      controller.attach();
      client.connected();
      client.announce('cam');
      expect(controller.stage, WebRTCStage.negotiating);
      // The socket died unnoticed: the request went out, nothing comes back.
      await tester.pump(const Duration(seconds: 14));
      expect(client.reconnects, 0);
      await tester.pump(const Duration(seconds: 2));
      expect(client.reconnects, 1);
      expect(client.sessions.single.closed, isTrue);
      expect(controller.stage, WebRTCStage.connecting);
      // The new channel connects and names the camera again: a new session starts at once.
      client.connected();
      expect(client.sessions, hasLength(2));
      client.sessions.last.streaming();
      expect(controller.stage, WebRTCStage.streaming);
      // Streaming in time: no rebuild.
      await tester.pump(const Duration(seconds: 30));
      expect(client.reconnects, 1);
      controller.dispose();
    },
  );

  testWidgets(
    'back from a long absence, the tab starts on a fresh signalling connection',
    (WidgetTester tester) async {
      final (WebRTCStreamController controller, _FakeClient client) =
          _streaming();
      // A glance away keeps the session and the socket.
      controller.pageHidden(true);
      await tester.pump(const Duration(seconds: 20));
      controller.pageHidden(false);
      expect(client.reconnects, 0);
      // Hours away, a laptop asleep in between: the old socket may carry nothing any more.
      controller.pageHidden(true);
      await tester.pump(const Duration(minutes: 3));
      expect(client.sessions.single.closed, isTrue);
      controller.pageHidden(false);
      expect(client.reconnects, 1);
      expect(controller.stage, WebRTCStage.connecting);
      client.connected();
      expect(client.sessions, hasLength(2));
      expect(controller.stage, WebRTCStage.negotiating);
      controller.dispose();
    },
  );

  test(
    'a picture that stops moving while streaming rebuilds the connection',
    () {
      final (WebRTCStreamController controller, _FakeClient client) =
          _streaming();
      // Moving frames: nothing happens, however long.
      for (var frames = 60; frames <= 600; frames += 60) {
        controller.reportFrames(frames);
      }
      expect(client.reconnects, 0);
      // The camera restarted behind a dead socket: the fifth unchanged count, 10 s on, acts.
      for (var i = 0; i < 4; i++) {
        controller.reportFrames(600);
      }
      expect(client.reconnects, 0);
      controller.reportFrames(600);
      expect(client.reconnects, 1);
      expect(client.sessions.single.closed, isTrue);
      expect(controller.stage, WebRTCStage.connecting);
      client.connected();
      expect(client.sessions, hasLength(2));
      controller.dispose();
    },
  );

  test(
    'a hidden tab or a stream not playing yet is not judged by its frames',
    () {
      final (WebRTCStreamController controller, _FakeClient client) =
          _streaming();
      // A hidden tab may not decode at all.
      controller.pageHidden(true);
      for (var i = 0; i < 10; i++) {
        controller.reportFrames(100);
      }
      controller.pageHidden(false);
      expect(client.reconnects, 0);
      // Nor a session still negotiating, whose count stays at 0.
      final _FakeClient fresh = _FakeClient();
      final WebRTCStreamController negotiating = WebRTCStreamController(
        fresh,
        reconnectionTimeoutMs: 5000,
      );
      negotiating.attach();
      fresh.connected();
      fresh.announce('cam');
      for (var i = 0; i < 10; i++) {
        negotiating.reportFrames(0);
      }
      expect(fresh.reconnects, 0);
      controller.dispose();
      negotiating.dispose();
    },
  );

  test('two playback reports give the frames per second between them', () {
    final (WebRTCStreamController controller, _) = _streaming();
    final DateTime t = DateTime(2026, 10, 14, 16);
    controller.reportPlayback(
      totalFrames: 300,
      droppedFrames: 0,
      width: 640,
      height: 480,
      at: t,
    );
    expect(controller.playback.value, isNull);
    controller.reportPlayback(
      totalFrames: 359,
      droppedFrames: 2,
      width: 640,
      height: 480,
      at: t.add(const Duration(seconds: 2)),
    );
    final PlaybackStats stats = controller.playback.value!;
    expect(stats.fps, closeTo(29.5, 0.01));
    expect((stats.dropped, stats.width, stats.height), (2, 640, 480));
    // A new session restarts the count: no rate from that, the last one stands.
    controller.reportPlayback(
      totalFrames: 10,
      droppedFrames: 0,
      width: 640,
      height: 480,
      at: t.add(const Duration(seconds: 4)),
    );
    expect(controller.playback.value, same(stats));
    controller.dispose();
  });
}
