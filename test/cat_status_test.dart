import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:omni_accelerant/Pages/StreamPage/cat_status.dart';
import 'package:omni_accelerant/l10n/app_localizations.dart';

const _inView =
    '{"ok":true,"name":"Garden Cam","cat":{"in_view":true,"last_seen":1791763273}}';
const _seenBefore =
    '{"ok":true,"name":"Garden Cam","cat":{"in_view":false,"last_seen":1791763273}}';
const _neverSeen =
    '{"ok":true,"name":"","cat":{"in_view":false,"last_seen":null}}';

Future<void> _pumpLine(WidgetTester tester, Future<String?> Function() fetch) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: CatStatusLine(fetch: fetch, fallbackName: 'Fallback Cam'),
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
      expect(CatStatus.fromHealthz(_neverSeen)!.lastSeen, isNull);
    });

    test('is null for anything but a cat cam answer', () {
      expect(CatStatus.fromHealthz('<!DOCTYPE html><html></html>'), isNull);
      expect(CatStatus.fromHealthz('{"ok":false}'), isNull);
      expect(CatStatus.fromHealthz('{"ok":true}'), isNull);
      expect(CatStatus.fromHealthz('[]'), isNull);
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
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an unnamed cat cam with no cat yet keeps the fallback name', (
    tester,
  ) async {
    await _pumpLine(tester, () async => _neverSeen);
    await tester.pump();
    expect(find.text('Fallback Cam'), findsOneWidget);
    expect(find.text('No cat seen yet'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

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
}
