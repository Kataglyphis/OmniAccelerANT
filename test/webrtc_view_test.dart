@TestOn('browser')
library;

import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

import 'package:omni_accelerant/Pages/StreamPage/stream_controller.dart';
import 'package:omni_accelerant/Pages/StreamPage/webrtc_view.dart';

import 'support/gst_signalling_stand_in.dart';

const String _url = 'ws://signalling.test/webrtc-ws';

// One page: the view's video, API and controller are process-wide, so each test starts where the last one left the stream.
void main() {
  LiveTestWidgetsFlutterBinding.ensureInitialized();
  // The live binding's throttled print loses a failure's report when the page goes.
  debugPrint = debugPrintSynchronously;
  late SignallingStandIn server;
  final Widget app = webrtcViewApp(
    WebRTCView(
      settings: webrtcTestSettings(
        _url,
        stunServers: <String>['stun:stun.test:3478'],
      ),
    ),
  );

  setUpAll(() async {
    server = await installSignallingStandIn(_url);
  });

  Future<void> mountStreaming(WidgetTester tester) async {
    await tester.pumpWidget(app);
    await pumpUntil(tester, 'streaming', streaming);
  }

  Future<void> withdrawCamera(WidgetTester tester) async {
    server.withdraw('cam-1');
    await pumpUntil(
      tester,
      'the camera gone',
      () => shows(l10n.webrtcCameraGone),
    );
  }

  testWidgets(
    'a first view walks from connecting to streaming, and the camera reaches its video',
    (WidgetTester tester) async {
      server.holdWelcome = true;
      await tester.pumpWidget(app);
      await pumpUntil(
        tester,
        'the connecting overlay',
        () => shows(l10n.webrtcConnecting) && shows(_url),
      );
      server.releaseWelcome();
      await pumpUntil(
        tester,
        'waiting for a camera',
        () => shows(l10n.webrtcWaitingForCamera) && shows(l10n.webrtcNoCamera),
      );
      server.holdOffer = true;
      server.announce('cam-1');
      await pumpUntil(
        tester,
        'negotiating',
        () =>
            shows(l10n.webrtcNegotiating) &&
            shows(l10n.webrtcExchangingCandidates),
      );
      expect(server.session!.producerId, 'cam-1');
      server.releaseOffer();
      await pumpUntil(tester, 'streaming', streaming);

      expect(iceServerUrls(server.consumerConfigs.toDart.single), <Object?>[
        <Object?>['stun:stun.test:3478'],
      ]);
      final web.HTMLVideoElement video = server.video!;
      expect((video.srcObject! as web.MediaStream).getVideoTracks().length, 1);
      expect(await framesAdvance(tester, video), isTrue);
      // The stats panel's numbers: the view reads the video every 2 s, and two reads make a rate.
      await pumpUntil(
        tester,
        'playback stats',
        () => playbackStats()?.value != null,
      );
      final PlaybackStats stats = playbackStats()!.value!;
      expect((stats.width, stats.height), (64, 48));
      expect(stats.fps, greaterThan(5));
    },
  );

  testWidgets(
    'a camera that leaves ends its session and empties the video; back, it streams again',
    (WidgetTester tester) async {
      await mountStreaming(tester);
      final String first = server.session!.id;
      await withdrawCamera(tester);
      expect(shows(l10n.webrtcWaitingForCamera), isTrue);
      expect(server.video!.srcObject, isNull);
      server.announce('cam-1');
      await pumpUntil(tester, 'streaming again', streaming);
      expect(server.session!.id, isNot(first));
      expect(await framesAdvance(tester, server.video!), isTrue);
    },
  );

  testWidgets(
    'a dropped signalling socket says it is retrying, and the view streams once it is back',
    (WidgetTester tester) async {
      await mountStreaming(tester);
      // A second camera makes the view try it while gstwebrtc-api has no channel, and get no session.
      server.announce('cam-2');
      // A closed socket delivers nothing it still had queued; the announcement has to land first.
      await tester.pump(const Duration(milliseconds: 100));
      final int sockets = server.sockets.length;
      server.holdWelcome = true;
      server.drop();
      await pumpUntil(
        tester,
        'the retry message',
        () =>
            shows(l10n.webrtcConnecting) &&
            shows(l10n.webrtcSignallingLost(200)),
      );
      await pumpUntil(
        tester,
        'gstwebrtc-api reopening the socket',
        () => server.sockets.length == sockets + 1,
      );
      server.releaseWelcome();
      await pumpUntil(tester, 'streaming again', streaming);
      expect(server.session!.producerId, 'cam-1');
      server.withdraw('cam-2');
    },
  );

  testWidgets(
    'an offer the browser rejects fails the session, and the retry streams',
    (WidgetTester tester) async {
      await mountStreaming(tester);
      await withdrawCamera(tester);
      server.corruptOffers = 1;
      server.announce('cam-1');
      await pumpUntil(
        tester,
        'the failure',
        () =>
            shows(l10n.webrtcFailed) &&
            shows(l10n.webrtcPeerError) &&
            find.byIcon(Icons.error_outline).evaluate().isNotEmpty,
      );
      final int started = server.startedSessions;
      await pumpUntil(tester, 'the retry streaming', streaming);
      expect(server.startedSessions, started + 1);
    },
  );

  testWidgets(
    'a session whose start cannot be sent says so, and the retry streams',
    (WidgetTester tester) async {
      await mountStreaming(tester);
      await withdrawCamera(tester);
      server.failNextSend('startSession');
      server.announce('cam-1');
      await pumpUntil(
        tester,
        'the failure',
        () => shows(l10n.webrtcFailed) && shows(l10n.webrtcPeerNotStarted),
      );
      await pumpUntil(tester, 'the retry streaming', streaming);
    },
  );

  testWidgets(
    'a session the camera ends while it stays announced is caught by its frozen picture',
    (WidgetTester tester) async {
      await mountStreaming(tester);
      final String ended = server.session!.id;
      final int sockets = server.sockets.length;
      server.endSession();
      // Five unchanged 2 s frame counts in a row rebuild the signalling connection.
      await pumpUntil(
        tester,
        'a new signalling socket',
        () => server.sockets.length == sockets + 1,
        timeout: const Duration(seconds: 30),
      );
      await pumpUntil(
        tester,
        'a new session streaming',
        () => streaming() && server.session?.id != ended,
      );
      expect(await framesAdvance(tester, server.video!), isTrue);
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );

  testWidgets('a hidden tab opens no session until it is shown', (
    WidgetTester tester,
  ) async {
    await mountStreaming(tester);
    await withdrawCamera(tester);
    server.setHidden(true);
    final int started = server.startedSessions;
    server.announce('cam-1');
    await tester.pump(const Duration(seconds: 1));
    // ObservANT encodes per viewer, and nobody sees this one.
    expect(server.startedSessions, started);
    server.setHidden(false);
    await pumpUntil(tester, 'streaming once shown', streaming);
    expect(server.startedSessions, started + 1);
  });

  testWidgets(
    'a remount keeps the session and plays the video the browser paused',
    (WidgetTester tester) async {
      await mountStreaming(tester);
      final web.HTMLVideoElement video = server.video!;
      final String session = server.session!.id;
      // flutter test renders no platform views, so the test puts the video where the engine would.
      web.document.body!.append(video);
      await pumpUntil(tester, 'the video playing', () => !video.paused);
      await tester.pumpWidget(const SizedBox());
      video.remove();
      await pumpUntil(tester, 'the browser pausing it', () => video.paused);
      web.document.body!.append(video);
      await tester.pumpWidget(app);
      await pumpUntil(tester, 'the video playing again', () => !video.paused);
      expect(streaming(), isTrue);
      expect(server.session!.id, session);
      video.remove();
    },
  );

  testWidgets(
    'a camera that offers a control channel gets the video\'s input through it',
    (WidgetTester tester) async {
      await mountStreaming(tester);
      await withdrawCamera(tester);
      server.offerControlChannel = true;
      server.announce('cam-1');
      await pumpUntil(tester, 'streaming', streaming);
      final web.HTMLVideoElement video = server.video!;
      // gstwebrtc-api's RemoteController marks the element it listens on.
      await pumpUntil(
        tester,
        'the remote controller on the video',
        () => video.getAttribute('tabindex') == '0',
      );
      video.dispatchEvent(
        web.MouseEvent('mousedown', web.MouseEventInit(button: 0)),
      );
      await pumpUntil(
        tester,
        'the press on the control channel',
        () => server.session!.control.length > 0,
      );
      final Map<Object?, Object?> message =
          server.session!.control.toDart.first.dartify()!
              as Map<Object?, Object?>;
      final Map<Object?, Object?> request =
          message['request']! as Map<Object?, Object?>;
      expect(request['type'], 'navigationEvent');
      expect(
        (request['event']! as Map<Object?, Object?>)['event'],
        'MouseButtonPress',
      );
      server.offerControlChannel = false;
    },
  );

  testWidgets(
    'leaving the page ends the session once the keep-alive runs out',
    (WidgetTester tester) async {
      await mountStreaming(tester);
      final StandInSession session = server.session!;
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 25));
      expect(session.ended, isFalse);
      await pumpUntil(
        tester,
        'the session ending',
        () => session.ended,
        timeout: const Duration(seconds: 10),
      );
      expect(server.video!.srcObject, isNull);
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );
}
