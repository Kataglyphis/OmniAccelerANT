import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_accelerant/Pages/StreamPage/dev_stats.dart';
import 'package:omni_accelerant/Pages/StreamPage/stream_controller.dart';
import 'package:omni_accelerant/l10n/app_localizations.dart';

const _healthz =
    '{"ok":true,"frame":{"fps":30,"width":640,"height":480},"viewers":1,'
    '"stats":{"capture_fps":29.8,"model_ms":84.4,"model_runs_per_s":0.2,'
    '"cpu_percent":10.5,"cores":4,"rss_mb":220.3,"load_1m":0.13,'
    '"temperature_c":51.25,"uptime_s":3725}}';

Future<void> _pumpPanel(
  WidgetTester tester,
  Future<String?> Function() fetch,
  ValueListenable<PlaybackStats?>? playback,
) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: DevStatsPanel(fetch: fetch, playback: () => playback),
      ),
    ),
  );
}

void main() {
  group('ServerStats.fromHealthz', () {
    test('reads every number ObservANT reports', () {
      final stats = ServerStats.fromHealthz(_healthz)!;
      expect(stats.captureFps, 29.8);
      expect(stats.configuredFps, 30);
      expect(stats.modelMs, 84.4);
      expect(stats.modelRunsPerSecond, 0.2);
      expect(stats.cpuPercent, 10.5);
      expect(stats.cores, 4);
      expect(stats.rssMb, 220.3);
      expect(stats.load1m, 0.13);
      expect(stats.temperatureC, 51.25);
      expect(stats.uptime, const Duration(seconds: 3725));
      expect(stats.viewers, 1);
    });

    test('a number ObservANT cannot measure stays null', () {
      final stats = ServerStats.fromHealthz(
        '{"ok":true,"stats":{"capture_fps":30,"temperature_c":null}}',
      )!;
      expect(stats.captureFps, 30);
      expect(stats.temperatureC, isNull);
      expect(stats.cpuPercent, isNull);
    });

    test('no stats, no JSON or no answer is no stats', () {
      expect(ServerStats.fromHealthz('{"ok":true}'), isNull);
      expect(ServerStats.fromHealthz('<html>'), isNull);
      expect(ServerStats.fromHealthz(null), isNull);
    });
  });

  testWidgets(
    'the panel opens on a tap, polls while open and stops when closed',
    (tester) async {
      var polls = 0;
      final browser = ValueNotifier<PlaybackStats?>(
        const PlaybackStats(fps: 29.5, dropped: 3, width: 640, height: 480),
      );
      await _pumpPanel(tester, () async {
        polls++;
        return _healthz;
      }, browser);
      expect(find.text('Stats'), findsOneWidget);
      expect(polls, 0);

      await tester.tap(find.text('Stats'));
      await tester.pump();
      await tester.pump();
      expect(polls, 1);
      expect(find.text('29.8 of 30 fps'), findsOneWidget);
      expect(find.text('84 ms per run, 0.20 runs/s'), findsOneWidget);
      expect(
        find.text('10.5 % of one core, 4 cores, load 0.13'),
        findsOneWidget,
      );
      expect(find.text('220 MB'), findsOneWidget);
      expect(find.text('51.3 °C'), findsOneWidget);
      expect(find.text('1 h 2 min'), findsOneWidget);
      expect(find.text('29.5 fps, 640 × 480, 3 dropped'), findsOneWidget);

      browser.value = const PlaybackStats(
        fps: 24,
        dropped: 3,
        width: 640,
        height: 480,
      );
      await tester.pump();
      expect(find.text('24.0 fps, 640 × 480, 3 dropped'), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      expect(polls, 2);
      await tester.tap(find.text('Stats'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 10));
      expect(polls, 2);
      expect(find.text('220 MB'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('with nothing to show it says so', (tester) async {
    await _pumpPanel(tester, () async => null, null);
    await tester.tap(find.text('Stats'));
    await tester.pump();
    await tester.pump();
    expect(
      find.text(
        'No numbers yet: the camera reports none, and the browser plays nothing.',
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });
}
