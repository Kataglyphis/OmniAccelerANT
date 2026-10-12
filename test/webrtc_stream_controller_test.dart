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
}
