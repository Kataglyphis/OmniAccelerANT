@TestOn('browser')
library;

import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:omni_accelerant/Pages/StreamPage/webrtc_view.dart';

import 'support/gst_signalling_stand_in.dart';

const String _url = 'ws://signalling.test/webrtc-ws';

void main() {
  LiveTestWidgetsFlutterBinding.ensureInitialized();
  // The live binding's throttled print loses a failure's report when the page goes.
  debugPrint = debugPrintSynchronously;

  testWidgets(
    'the first view sets the producer and the ICE servers for the page, and a later URL changes nothing',
    (WidgetTester tester) async {
      final SignallingStandIn server = await installSignallingStandIn(_url);
      server.announce('cam-1');
      server.announce('cam-2');
      await tester.pumpWidget(
        webrtcViewApp(
          WebRTCView(
            settings: webrtcTestSettings(_url),
            producerIdToConsume: 'cam-2',
          ),
        ),
      );
      await pumpUntil(tester, 'streaming', streaming);
      expect(server.session!.producerId, 'cam-2');
      // No ICE servers configured means none, not gstwebrtc-api's public STUN default.
      expect(iceServerUrls(server.consumerConfigs.toDart.single), isEmpty);

      final List<String> logs = <String>[];
      final DebugPrintCallback print = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) => logs.add('$message');
      try {
        // A new State, as a page change makes; the same widget in place would only update the old one.
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          webrtcViewApp(
            WebRTCView(
              settings: webrtcTestSettings('ws://elsewhere.test/webrtc-ws'),
            ),
          ),
        );
        await tester.pump(const Duration(seconds: 1));
      } finally {
        debugPrint = print;
      }
      expect(streaming(), isTrue);
      expect(server.sockets.length, 1);
      expect(server.session!.producerId, 'cam-2');
      expect(logs, contains(contains('cannot be re-targeted')));
    },
  );
}
