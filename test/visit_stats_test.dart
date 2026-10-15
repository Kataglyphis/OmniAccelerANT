import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_accelerant/Pages/StreamPage/visit_stats.dart';
import 'package:omni_accelerant/l10n/app_localizations.dart';

final _now = DateTime(2026, 10, 15, 18, 30);

int _unix(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

/// `/visits` as ObservANT answers it, newest first.
String _visits(List<(DateTime, int?)> visits) => jsonEncode({
  'days': 30,
  'visits': [
    for (final (arrived, stayed) in visits) [_unix(arrived), stayed],
  ],
});

Future<void> _pump(WidgetTester tester, Future<String?> Function() fetch) =>
    tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: SingleChildScrollView(
            child: VisitStatsPanel(fetch: fetch, now: () => _now),
          ),
        ),
      ),
    );

void main() {
  group('staysFromJson', () {
    test('reads each visit and its stay, an open one without', () {
      final stays = staysFromJson(
        _visits([
          (DateTime(2026, 10, 15, 7), null),
          (DateTime(2026, 10, 14, 22), 90),
        ]),
      );
      expect(stays.map((s) => s.arrived), [
        DateTime(2026, 10, 15, 7),
        DateTime(2026, 10, 14, 22),
      ]);
      expect(stays.map((s) => s.stayed), [null, const Duration(seconds: 90)]);
    });

    test('anything but a list of pairs reads as no visits', () {
      expect(staysFromJson(null), isEmpty);
      expect(staysFromJson('{"visits": "many"}'), isEmpty);
      expect(staysFromJson('{"visits": [["noon", 5], [1, 2, 3]]}'), isEmpty);
    });
  });

  group('VisitStats.of', () {
    test('counts per calendar day up to today and per hour, in local time', () {
      final stays = staysFromJson(
        _visits([
          (DateTime(2026, 10, 15, 7, 5), null),
          (DateTime(2026, 10, 15, 7, 50), 120),
          (DateTime(2026, 10, 14, 23, 59), 60),
          (DateTime(2026, 10, 2, 0, 1), 30),
          // Fourteen days before today's date: one day past the window.
          (DateTime(2026, 10, 1, 12), 10),
        ]),
      );
      final stats = VisitStats.of(stays, _now);
      expect(stats.perDay, hasLength(14));
      expect(stats.today, 2);
      expect(
        stats.perDay[12],
        1,
        reason: 'yesterday, a minute before midnight',
      );
      expect(stats.perDay.first, 1, reason: 'the 2nd, the window\'s first day');
      expect(stats.total, 4);
      expect(stats.perHour[7], 2);
      expect(stats.perHour[23], 1);
      expect(stats.perHour[0], 1);
      // Only the visits that left: (120 + 60 + 30) / 3.
      expect(stats.averageStay, const Duration(seconds: 70));
    });

    test('a visit after now does not count, and no visit has no average', () {
      final stays = staysFromJson(_visits([(DateTime(2026, 10, 16, 8), null)]));
      final stats = VisitStats.of(stays, _now, days: 7);
      expect(stats.perDay, hasLength(7));
      expect(stats.total, 0);
      expect(stats.averageStay, isNull);
    });
  });

  group('VisitStatsPanel', () {
    testWidgets('opens on a tap with the summary and both charts', (
      tester,
    ) async {
      var asked = 0;
      await _pump(tester, () async {
        asked++;
        return _visits([
          (DateTime(2026, 10, 15, 7, 5), null),
          (DateTime(2026, 10, 15, 6), 180),
          (DateTime(2026, 10, 12, 21), 60),
        ]);
      });
      expect(find.text('Visits'), findsOneWidget);
      expect(asked, 0, reason: 'nothing is fetched while closed');
      await tester.tap(find.text('Visits'));
      await tester.pumpAndSettle();
      expect(asked, 1);
      expect(find.text('2 today, 3 in 14 days'), findsOneWidget);
      expect(find.text('Average stay: 2 min'), findsOneWidget);
      expect(find.text('Per day'), findsOneWidget);
      expect(find.text('By time of day'), findsOneWidget);
      expect(find.byType(Tooltip), findsNWidgets(14 + 24));
      // Closed again, it stops asking.
      await tester.tap(find.text('Visits'));
      await tester.pump(const Duration(minutes: 2));
      expect(asked, 1);
    });

    testWidgets('says so when there was no visit', (tester) async {
      await _pump(tester, () async => _visits(const []));
      await tester.tap(find.text('Visits'));
      await tester.pumpAndSettle();
      expect(find.text('No visits in the last 14 days.'), findsOneWidget);
    });

    testWidgets('a camera that does not answer leaves the button alone', (
      tester,
    ) async {
      await _pump(tester, () async => null);
      await tester.tap(find.text('Visits'));
      await tester.pumpAndSettle();
      expect(find.text('Per day'), findsNothing);
      expect(find.text('Visits'), findsOneWidget);
    });
  });
}
