import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:omni_accelerant/Pages/StreamPage/cat_cam_peers.dart';
import 'package:omni_accelerant/Pages/StreamPage/cat_status.dart';
import 'package:omni_accelerant/l10n/app_localizations.dart';
import 'package:url_launcher/link.dart';

const _own =
    '{"ok":true,"name":"Büro","peers":["http://10.0.0.2:8080/","http://10.0.0.3:8080"],'
    '"cat":{"in_view":false,"last_seen":null,"visits":0,"recent":[]}}';
const _trough =
    '{"ok":true,"name":"Futtertrog","peers":[],'
    '"cat":{"in_view":true,"last_seen":1791763273,"visits":3,"recent":[]}}';

Widget _fakePicture(String url) => Text('picture $url');

Future<void> _pump(
  WidgetTester tester,
  Future<String?> Function() own,
  Map<String, String?> others, {
  List<String>? asked,
}) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: CatCamPeers(
          fetchOwn: own,
          fetchFrom: (url) async {
            asked?.add(url);
            return others[url];
          },
          picture: _fakePicture,
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
  });

  test('a /healthz names its peers', () {
    expect(CatStatus.fromHealthz(_own)!.peers, [
      'http://10.0.0.2:8080/',
      'http://10.0.0.3:8080',
    ]);
    expect(CatStatus.fromHealthz(_trough)!.peers, isEmpty);
  });

  testWidgets('a cat cam without peers shows no overview', (tester) async {
    await _pump(tester, () async => _trough, const {});
    await tester.pump();
    expect(find.text('Other cat cams'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'each peer shows its name, picture and cat, or that it is not reachable',
    (tester) async {
      final asked = <String>[];
      await _pump(tester, () async => _own, const {
        'http://10.0.0.2:8080/healthz': _trough,
      }, asked: asked);
      await tester.pump();
      expect(asked, [
        'http://10.0.0.2:8080/healthz',
        'http://10.0.0.3:8080/healthz',
      ]);
      expect(find.text('Other cat cams'), findsOneWidget);
      expect(find.text('Futtertrog'), findsOneWidget);
      expect(find.text('Cat in view'), findsOneWidget);
      expect(
        find.textContaining('picture http://10.0.0.2:8080/snapshot.jpg'),
        findsOneWidget,
      );
      // The silent one keeps its place, named by its address, with no picture.
      expect(find.text('10.0.0.3'), findsOneWidget);
      expect(find.text('Not reachable'), findsOneWidget);
      expect(find.textContaining('picture http://10.0.0.3:8080'), findsNothing);
      final links = [
        for (final l in tester.widgetList<Link>(find.byType(Link)))
          l.uri.toString(),
      ];
      expect(links, [
        'http://10.0.0.2:8080/#/stream',
        'http://10.0.0.3:8080/#/stream',
      ]);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('the overview refreshes on its interval', (tester) async {
    final others = <String, String?>{'http://10.0.0.2:8080/healthz': null};
    await _pump(tester, () async => _own, others);
    await tester.pump();
    expect(find.text('Not reachable'), findsNWidgets(2));
    others['http://10.0.0.2:8080/healthz'] = _trough;
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    expect(find.text('Not reachable'), findsOneWidget);
    expect(find.text('Futtertrog'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
