import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

import 'package:omni_accelerant/l10n/app_localizations.dart';
import 'package:omni_accelerant/settings/webrtc_settings.dart';

/// The test page's ObservANT: `gst_signalling_stand_in.js`, in front of the gstwebrtc-api the web build ships.
extension type SignallingStandIn._(JSObject _) implements JSObject {
  /// A producer comes online, as `peerStatusChanged` with the producer role.
  external void announce(String producerId);

  /// A producer leaves: its sessions end, then it is gone from the list.
  external void withdraw(String producerId);

  /// The camera ends the open session but stays announced.
  external void endSession();

  /// The server closes every signalling socket.
  external void drop();

  /// Sets `document.hidden` and fires `visibilitychange`, as the browser does when the tab hides or shows.
  external void setHidden(bool hidden);

  /// Sends `welcome` to sockets opened while [holdWelcome] was set.
  external void releaseWelcome();

  /// Sends the offer to sessions started while [holdOffer] was set.
  external void releaseOffer();

  external set holdWelcome(bool hold);
  external set holdOffer(bool hold);
  external set corruptOffers(int count);
  external set offerControlChannel(bool offer);

  /// The viewer's next `send` of a [type] message throws, as a socket still connecting does.
  external void failNextSend(String type);

  /// Every message type the viewer sent, in order.
  external JSArray<JSString> get received;

  /// Each signalling socket the viewer opened.
  external JSArray<JSObject> get sockets;

  /// What Chrome made of each RTCPeerConnection config gstwebrtc-api passed.
  external JSArray<JSObject> get consumerConfigs;

  /// The newest session not yet ended, or `null`.
  external StandInSession? get session;

  /// The element the view last gave a stream, or `null` before it did.
  external web.HTMLVideoElement? get video;
}

/// One session as the stand-in server keeps it.
extension type StandInSession._(JSObject _) implements JSObject {
  external String get id;
  external String get producerId;
  external bool get ended;

  /// What the viewer sent over the `control` data channel, parsed.
  external JSArray<JSAny> get control;
}

extension StandInCounts on SignallingStandIn {
  /// How many sessions the viewer asked the server to start.
  int get startedSessions =>
      received.toDart.where((t) => t.toDart == 'startSession').length;
}

/// Loads the gstwebrtc-api build `web/index.html` imports, then the stand-in that answers [signallingUrl].
Future<SignallingStandIn> installSignallingStandIn(String signallingUrl) async {
  // The browser cannot read the checkout; a hybrid isolate on the VM reads what the page would load.
  final channel = spawnHybridCode(r'''
import 'dart:io';
import 'package:stream_channel/stream_channel.dart';

void hybridMain(StreamChannel<Object?> channel) {
  final String index = File('web/index.html').readAsStringSync();
  final Match? import = RegExp(r"import GstWebRTCAPI from '\./(javascript/webrtc/gstwebrtc-api-[^']+\.esm\.js)'").firstMatch(index);
  channel.sink.add(import == null ? null : File('web/${import[1]}').readAsStringSync());
  channel.sink.close();
}
''');
  final Object? source = await channel.stream.first;
  if (source is! String) {
    throw StateError('web/index.html no longer imports a gstwebrtc-api build');
  }
  final web.Blob blob = web.Blob(
    <JSAny>[source.toJS].toJS,
    web.BlobPropertyBag(type: 'text/javascript'),
  );
  await importModule(web.URL.createObjectURL(blob).toJS).toDart;
  final JSObject standIn = await importModule(
    '/support/gst_signalling_stand_in.js'.toJS,
  ).toDart;
  return standIn.callMethod<SignallingStandIn>(
    'install'.toJS,
    signallingUrl.toJS,
  );
}

/// `webrtc_settings.json` as the view reads it, with this test's signalling URL and ICE servers.
WebRTCSettings webrtcTestSettings(
  String signallingUrl, {
  List<String> stunServers = const <String>[],
  int reconnectionTimeoutMs = 200,
}) => WebRTCSettings.fromJsonFile(<String, dynamic>{
  'signalingServerUrl': signallingUrl,
  'reconnectionTimeoutMs': reconnectionTimeoutMs,
  'stunServers': stunServers,
  'turnServers': <String>[],
  'video': <String, dynamic>{
    'defaultWidth': 1280,
    'defaultHeight': 720,
    'defaultFramerate': 30,
    'defaultBitrateKbps': 2000,
  },
  'texture': <String, dynamic>{'width': 640, 'height': 480},
  'android': <String, dynamic>{'width': 320, 'height': 240, 'fps': 15},
});

/// The English strings the view's overlay shows.
final AppLocalizations l10n = lookupAppLocalizations(const Locale('en'));

/// [view] as the Stream page holds it, in English.
Widget webrtcViewApp(Widget view) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: SizedBox(width: 320, height: 240, child: view)),
);

/// Pumps real frames until [done]; the stream's events come from the browser, not from fake time.
Future<void> pumpUntil(
  WidgetTester tester,
  String what,
  bool Function() done, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final DateTime deadline = DateTime.now().add(timeout);
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) fail('no $what within $timeout');
    await tester.pump(const Duration(milliseconds: 50));
  }
}

bool shows(String text) => find.text(text).evaluate().isNotEmpty;

/// The view is mounted and shows the video bare, without its status overlay.
bool streaming() =>
    find.byType(HtmlElementView).evaluate().isNotEmpty &&
    find.byType(CircularProgressIndicator).evaluate().isEmpty &&
    find.byIcon(Icons.error_outline).evaluate().isEmpty;

/// The video decodes new frames over half a second.
Future<bool> framesAdvance(
  WidgetTester tester,
  web.HTMLVideoElement video,
) async {
  final int before = video.getVideoPlaybackQuality().totalVideoFrames;
  await tester.pump(const Duration(milliseconds: 500));
  return video.getVideoPlaybackQuality().totalVideoFrames > before;
}

/// The `urls` of each ICE server in a config Chrome reports.
List<Object?> iceServerUrls(JSObject config) => <Object?>[
  for (final Object? server
      in config.getProperty<JSAny?>('iceServers'.toJS).dartify()!
          as List<Object?>)
    (server! as Map<Object?, Object?>)['urls'],
];
