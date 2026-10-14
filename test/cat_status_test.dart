import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:omni_accelerant/Pages/StreamPage/cat_status.dart';
import 'package:omni_accelerant/l10n/app_localizations.dart';
import 'package:url_launcher/link.dart';

const _inView =
    '{"ok":true,"name":"Garden Cam","cat":{"in_view":true,"last_seen":1791763273,"visits":3,'
    '"recent":[{"arrived":1791763200,"stayed_s":null}]}}';
const _seenBefore =
    '{"ok":true,"name":"Garden Cam","cat":{"in_view":false,"last_seen":1791763273,"visits":3,'
    '"recent":[{"arrived":1791763088,"stayed_s":185},{"arrived":1791700000,"stayed_s":20}]}}';
const _neverSeen =
    '{"ok":true,"name":"","cat":{"in_view":false,"last_seen":null,"visits":0,"recent":[]}}';

Widget _fakeArrival(String url, String label) =>
    Text('picture $url ($label)', key: const Key('arrival'));

Future<void> _pumpLine(WidgetTester tester, Future<String?> Function() fetch) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: CatStatusLine(
          fetch: fetch,
          fallbackName: 'Fallback Cam',
          arrivalImage: _fakeArrival,
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('de');
  });

  group('CatStatus.fromHealthz', () {
    test('reads the name, the cat and when it was last seen', () {
      final status = CatStatus.fromHealthz(_seenBefore)!;
      expect(status.name, 'Garden Cam');
      expect(status.inView, isFalse);
      expect(
        status.lastSeen,
        DateTime.fromMillisecondsSinceEpoch(1791763273 * 1000),
      );
      expect(status.visits, 3);
      expect(status.recent, hasLength(2));
      expect(status.recent.first.stayed, const Duration(seconds: 185));
      expect(
        status.recent.last.arrived,
        DateTime.fromMillisecondsSinceEpoch(1791700000 * 1000),
      );
      expect(CatStatus.fromHealthz(_inView)!.recent.single.stayed, isNull);
      expect(CatStatus.fromHealthz(_neverSeen)!.lastSeen, isNull);
      expect(CatStatus.fromHealthz(_neverSeen)!.visits, 0);
      expect(CatStatus.fromHealthz(_neverSeen)!.recent, isEmpty);
    });

    test('reads which arrival the clip shows, and none without one', () {
      final withClip = CatStatus.fromHealthz(
        _inView.replaceFirst('"visits":3', '"visits":3,"clip":1791763200'),
      )!;
      expect(withClip.clip, DateTime.fromMillisecondsSinceEpoch(1791763200000));
      expect(withClip.hasLatestClip, isTrue);
      expect(CatStatus.fromHealthz(_inView)!.clip, isNull);
      expect(CatStatus.fromHealthz(_inView)!.hasLatestClip, isFalse);
    });

    test('reads every kept clip, newest first', () {
      final status = CatStatus.fromHealthz(
        _inView.replaceFirst('"visits":3', '"visits":3,"clips":[30,20,"x",10]'),
      )!;
      expect(status.clips, <DateTime>[
        for (final int t in <int>[30, 20, 10])
          DateTime.fromMillisecondsSinceEpoch(t * 1000),
      ]);
      expect(CatStatus.fromHealthz(_inView)!.clips, isEmpty);
    });

    test('is null for anything but a cat cam answer', () {
      expect(CatStatus.fromHealthz('<!DOCTYPE html><html></html>'), isNull);
      expect(CatStatus.fromHealthz('{"ok":false}'), isNull);
      expect(CatStatus.fromHealthz('{"ok":true}'), isNull);
      expect(CatStatus.fromHealthz('{"ok":"yes","cat":{}}'), isNull);
      expect(CatStatus.fromHealthz('[]'), isNull);
    });

    test('a cat cam that is not ok is still one, with its problem', () {
      final sick = CatStatus.fromHealthz(
        _inView.replaceFirst(
          '"ok":true',
          '"ok":false,"problem":"no frame for 45 s"',
        ),
      )!;
      expect(sick.problem, 'no frame for 45 s');
      expect(sick.name, 'Garden Cam');
      expect(CatStatus.fromHealthz(_inView)!.problem, isNull);
    });

    test('knows when the privacy filter pixelates the picture', () {
      final private = CatStatus.fromHealthz(
        _inView.replaceFirst('"ok":true', '"ok":true,"privacy":"pixelate"'),
      )!;
      expect(private.pixelated, isTrue);
      expect(CatStatus.fromHealthz(_inView)!.pixelated, isFalse);
      final off = CatStatus.fromHealthz(
        _inView.replaceFirst('"ok":true', '"ok":true,"privacy":"off"'),
      )!;
      expect(off.pixelated, isFalse);
    });
  });

  test('last seen is a time today and a date before', () {
    final now = DateTime(2026, 10, 12, 20, 0);
    expect(formatLastSeen(DateTime(2026, 10, 12, 14, 32), now, 'en'), '14:32');
    expect(
      formatLastSeen(DateTime(2026, 10, 11, 14, 32), now, 'en'),
      'Oct 11 14:32',
    );
    expect(
      formatLastSeen(DateTime(2026, 10, 11, 14, 32), now, 'de'),
      '11. Okt. 14:32',
    );
  });

  test('a stay is whole minutes, <1 below one', () {
    expect(stayMinutes(const Duration(seconds: 59)), '<1');
    expect(stayMinutes(const Duration(seconds: 60)), '1');
    expect(stayMinutes(const Duration(seconds: 185)), '3');
    expect(stayMinutes(const Duration(minutes: 95)), '95');
  });

  testWidgets('recent visits list each arrival and how long the cat stayed', (
    tester,
  ) async {
    await _pumpLine(tester, () async => _seenBefore);
    await tester.pump();
    expect(find.textContaining('Recent visits: '), findsOneWidget);
    expect(find.textContaining('(3 min) · '), findsOneWidget);
    expect(find.textContaining('(<1 min)'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a visit still going on shows no stay', (tester) async {
    await _pumpLine(tester, () async => _inView);
    await tester.pump();
    expect(find.textContaining('Recent visits: '), findsOneWidget);
    expect(find.textContaining(' min)'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a cat in view shows under the cat cam name', (tester) async {
    await _pumpLine(tester, () async => _inView);
    await tester.pump();
    expect(find.text('Garden Cam'), findsOneWidget);
    expect(find.text('Cat in view'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a cat seen before shows when', (tester) async {
    await _pumpLine(tester, () async => _seenBefore);
    await tester.pump();
    expect(find.textContaining('Cat last seen: '), findsOneWidget);
    expect(
      find.text("picture /arrival.jpg?visit=3 (The cat's last arrival)"),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the picture changes with a new visit, not with each sighting', (
    tester,
  ) async {
    var body = _inView;
    await _pumpLine(tester, () async => body);
    await tester.pump();
    expect(find.textContaining('/arrival.jpg?visit=3 '), findsOneWidget);
    body = _inView.replaceFirst('1791763273', '1791763290');
    await tester.pump(const Duration(seconds: 5));
    expect(find.textContaining('/arrival.jpg?visit=3 '), findsOneWidget);
    body = _inView.replaceFirst('"visits":3', '"visits":4');
    await tester.pump(const Duration(seconds: 5));
    expect(find.textContaining('/arrival.jpg?visit=4 '), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the clip shows once it is of the newest arrival', (
    tester,
  ) async {
    // The cat cam encodes a clip some seconds after the arrival it shows.
    var body = _inView.replaceFirst(
      '"visits":3',
      '"visits":3,"clip":1791700000',
    );
    await _pumpLine(tester, () async => body);
    await tester.pump();
    expect(find.text('Watch the arrival'), findsNothing);
    body = _inView.replaceFirst('"visits":3', '"visits":3,"clip":1791763200');
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Watch the arrival'), findsOneWidget);
    final Link link = tester.widget<Link>(find.byType(Link));
    expect(link.uri.toString(), '/arrival.mp4?t=1791763200');
    expect(link.target, LinkTarget.blank);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('earlier clips are linked beside the newest arrival\'s', (
    tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    // Only the newest arrival's clip: no list of earlier ones.
    var body = _inView.replaceFirst(
      '"visits":3',
      '"visits":3,"clip":1791763200,"clips":[1791763200]',
    );
    await _pumpLine(tester, () async => body);
    await tester.pump();
    expect(find.text('Watch the arrival'), findsOneWidget);
    expect(find.text('Earlier videos:'), findsNothing);

    body = _inView.replaceFirst(
      '"visits":3',
      '"visits":3,"clip":1791763200,"clips":[1791763200,1791700000,1791600000]',
    );
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Earlier videos:'), findsOneWidget);
    final List<String> links = <String>[
      for (final Link l in tester.widgetList<Link>(find.byType(Link)))
        l.uri.toString(),
    ];
    expect(links, <String>[
      '/arrival.mp4?t=1791763200',
      '/arrival.mp4?t=1791700000',
      '/arrival.mp4?t=1791600000',
    ]);
    // A screen reader hears what each earlier link plays, not a bare time.
    expect(find.bySemanticsLabel(RegExp(r'^Video from ')), findsNWidgets(2));
    // Each earlier video shows its arrival's own picture, over a film icon for one not kept.
    expect(find.byIcon(Icons.movie_outlined), findsNWidgets(2));
    expect(
      find.textContaining('picture /arrival.jpg?t=1791700000 '),
      findsOneWidget,
    );
    expect(
      find.textContaining('picture /arrival.jpg?t=1791600000 '),
      findsOneWidget,
    );
    semantics.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an unnamed cat cam with no cat yet keeps the fallback name', (
    tester,
  ) async {
    await _pumpLine(tester, () async => _neverSeen);
    await tester.pump();
    expect(find.text('Fallback Cam'), findsOneWidget);
    expect(find.text('No cat seen yet'), findsOneWidget);
    expect(find.byKey(const Key('arrival')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'a long German line wraps on a narrow phone instead of overflowing',
    (tester) async {
      tester.view.physicalSize = const Size(220, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          home: Scaffold(
            body: Center(
              child: CatStatusLine(
                fetch: () async => _seenBefore,
                fallbackName: 'Fallback Cam',
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.textContaining('Katze zuletzt gesehen: '), findsOneWidget);
      expect(find.textContaining('Letzte Besuche: '), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('without a cat cam behind the page only the name shows', (
    tester,
  ) async {
    await _pumpLine(tester, () async => null);
    await tester.pump();
    expect(find.text('Fallback Cam'), findsOneWidget);
    expect(find.byType(Icon), findsNothing);
    await _pumpLine(tester, () async => throw StateError('offline'));
    await tester.pump(const Duration(seconds: 5));
    expect(find.byType(Icon), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'behind another tab it polls nothing, and polls at once on return',
    (tester) async {
      var polls = 0;
      var shown = true;
      late StateSetter flip;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                flip = setState;
                // What go_router's indexed stack does to a branch that is not shown.
                return TickerMode(
                  enabled: shown,
                  child: CatStatusLine(
                    fetch: () async {
                      polls++;
                      return _inView;
                    },
                    fallbackName: 'Fallback Cam',
                    arrivalImage: _fakeArrival,
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();
      expect(polls, 1);
      flip(() => shown = false);
      await tester.pump();
      await tester.pump(const Duration(seconds: 30));
      expect(polls, 1, reason: 'no poll while hidden');
      flip(() => shown = true);
      await tester.pump();
      await tester.pump();
      expect(polls, 2);
      await tester.pump(const Duration(seconds: 5));
      expect(polls, 3);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('a pixelating camera says so above the cat', (tester) async {
    await _pumpLine(
      tester,
      () async =>
          _inView.replaceFirst('"ok":true', '"ok":true,"privacy":"pixelate"'),
    );
    await tester.pump();
    expect(
      find.text(
        'Privacy filter on: everything but the detected animals is pixelated',
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.blur_on), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a camera with a problem says so above the cat', (tester) async {
    await _pumpLine(
      tester,
      () async => _inView.replaceFirst(
        '"ok":true',
        '"ok":false,"problem":"no camera found, streaming a test pattern"',
      ),
    );
    await tester.pump();
    expect(
      find.text(
        'The camera has a problem: no camera found, streaming a test pattern',
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.warning_amber), findsOneWidget);
    expect(find.text('Cat in view'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a cat cam that stops answering says since when, and recovers', (
    tester,
  ) async {
    String? body = _seenBefore;
    await _pumpLine(tester, () async => body);
    await tester.pump();
    expect(find.textContaining('Cat last seen'), findsOneWidget);
    body = null;
    await tester.pump(const Duration(seconds: 5));
    expect(find.textContaining('Camera unreachable since '), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off), findsOneWidget);
    // What it said last stays: its name and its visits.
    expect(find.text('Garden Cam'), findsOneWidget);
    expect(find.textContaining('Recent visits'), findsOneWidget);
    body = _seenBefore;
    await tester.pump(const Duration(seconds: 5));
    expect(find.textContaining('Camera unreachable'), findsNothing);
    expect(find.textContaining('Cat last seen'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('more than three visits fold out on a tap', (tester) async {
    final visits = [
      for (var i = 0; i < 5; i++)
        '{"arrived":${1791763000 - i * 600},"stayed_s":60}',
    ].join(',');
    await _pumpLine(
      tester,
      () async =>
          '{"ok":true,"name":"Garden Cam","cat":{"in_view":false,"last_seen":1791763060,'
          '"visits":5,"recent":[$visits]}}',
    );
    await tester.pump();
    String line() =>
        tester.widget<Text>(find.textContaining('Recent visits')).data!;
    expect(' · '.allMatches(line()), hasLength(2));
    await tester.tap(find.text('All 5 visits'));
    await tester.pump();
    expect(' · '.allMatches(line()), hasLength(4));
    await tester.tap(find.text('Fewer visits'));
    await tester.pump();
    expect(' · '.allMatches(line()), hasLength(2));
    await tester.pumpWidget(const SizedBox());
  });
}
