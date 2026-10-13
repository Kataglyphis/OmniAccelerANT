import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_accelerant/Pages/CameraSettingsPage/camera_settings.dart';
import 'package:omni_accelerant/l10n/app_localizations.dart';

const _healthz =
    '{"ok":true,"name":"Cat Cam Futtertrog","rotate":270,"score":0.45,'
    '"frame":{"width":640,"height":480,"fps":15},"camera":"imx708",'
    '"inference":true,"model_runs":1234,"cat":{"visits":7}}';

/// A cat cam that keeps what the page posts, as `/settings` does.
class _FakeCatCam {
  Map<String, Object> settings = {
    'name': 'Cat Cam Futtertrog',
    'rotate': 270,
    'score': 0.45,
  };
  final posts = <Map<String, Object>>[];
  bool accept = true;

  Future<String?> fetchSettings() async =>
      '{"name":"${settings['name']}","rotate":${settings['rotate']},"score":${settings['score']}}';

  Future<bool> save(Map<String, Object> update) async {
    posts.add(update);
    if (accept) {
      settings = {...settings, ...update};
    }
    return accept;
  }
}

Widget _fakePreview(String url) =>
    Text('preview $url', key: const Key('preview'));

Future<void> _pump(
  WidgetTester tester, {
  required Future<String?> Function() fetchSettings,
  Future<bool> Function(Map<String, Object>)? save,
  Future<String?> Function()? fetchHealthz,
  Locale locale = const Locale('en'),
}) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      home: Scaffold(
        body: SingleChildScrollView(
          child: CameraSettingsPanel(
            fetchSettings: fetchSettings,
            saveSettings: save ?? (_) async => true,
            fetchHealthz: fetchHealthz ?? () async => _healthz,
            preview: _fakePreview,
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('CatCamSettings.parse', () {
    test('reads name, rotation and score', () {
      final settings = CatCamSettings.parse(
        '{"name":"Büro","rotate":90,"score":0.5}',
      )!;
      expect(settings.name, 'Büro');
      expect(settings.rotate, 90);
      expect(settings.score, 0.5);
    });

    test('takes a whole-number score', () {
      expect(
        CatCamSettings.parse('{"name":"a","rotate":0,"score":1}')!.score,
        1.0,
      );
    });

    test('is null for anything but a cat cam answer', () {
      for (final body in <String?>[
        null,
        'not json',
        '[1, 2]',
        '{"name":"a","rotate":"90","score":0.5}',
        '{"rotate":90,"score":0.5}',
        '<!doctype html>',
      ]) {
        expect(CatCamSettings.parse(body), isNull, reason: body);
      }
    });
  });

  group('CatCamInfo.parse', () {
    test('reads the camera, its frame and what the model did', () {
      final info = CatCamInfo.parse(_healthz)!;
      expect(info.camera, 'imx708');
      expect((info.width, info.height, info.fps), (640, 480, 15));
      expect(info.inference, isTrue);
      expect(info.modelRuns, 1234);
      expect(info.visits, 7);
    });

    test('an older cat cam without a frame block still parses', () {
      final info = CatCamInfo.parse('{"ok":true,"camera":"x"}')!;
      expect(info.width, isNull);
      expect(info.modelRuns, 0);
    });

    test('is null without ok, or for garbage', () {
      expect(CatCamInfo.parse('{"ok":false}'), isNull);
      expect(CatCamInfo.parse('nope'), isNull);
      expect(CatCamInfo.parse(null), isNull);
    });
  });

  testWidgets(
    'without a cat cam the page says so and offers nothing to change',
    (tester) async {
      await _pump(tester, fetchSettings: () async => null);
      await tester.pump();
      expect(find.textContaining('No cat cam answers here'), findsOneWidget);
      expect(find.byType(Slider), findsNothing);
      expect(find.byKey(const Key('preview')), findsNothing);
    },
  );

  testWidgets('a failing fetch reads as no cat cam, not as an error', (
    tester,
  ) async {
    await _pump(
      tester,
      fetchSettings: () async => throw StateError('offline'),
      fetchHealthz: () async => throw StateError('offline'),
    );
    await tester.pump();
    expect(find.textContaining('No cat cam answers here'), findsOneWidget);
  });

  testWidgets('shows the preview, the settings and the camera info', (
    tester,
  ) async {
    final cam = _FakeCatCam();
    await _pump(tester, fetchSettings: cam.fetchSettings, save: cam.save);
    await tester.pump();
    expect(find.text('Camera settings'), findsOneWidget);
    expect(find.textContaining('preview /snapshot.jpg'), findsOneWidget);
    expect(find.text('270°'), findsOneWidget);
    expect(find.text('A cat counts from 45 % certainty'), findsOneWidget);
    expect(
      find.widgetWithText(TextField, 'Cat Cam Futtertrog'),
      findsOneWidget,
    );
    expect(find.textContaining('640 × 480'), findsOneWidget);
    expect(find.textContaining('15 fps'), findsOneWidget);
    expect(find.textContaining('imx708'), findsOneWidget);
    expect(find.textContaining('1234'), findsOneWidget);
  });

  testWidgets('the rotate buttons turn the picture a quarter each way', (
    tester,
  ) async {
    final cam = _FakeCatCam();
    await _pump(tester, fetchSettings: cam.fetchSettings, save: cam.save);
    await tester.pump();
    await tester.tap(find.byTooltip('Turn the picture right'));
    await tester.pumpAndSettle();
    // 270 and a quarter clockwise is upright again.
    expect(cam.posts.last, {'rotate': 0});
    expect(find.text('0°'), findsOneWidget);
    await tester.tap(find.byTooltip('Turn the picture left'));
    await tester.pumpAndSettle();
    expect(cam.posts.last, {'rotate': 270});
    expect(find.text('Saved'), findsOneWidget);
  });

  testWidgets('the slider posts the score once, when it is let go', (
    tester,
  ) async {
    final cam = _FakeCatCam();
    await _pump(tester, fetchSettings: cam.fetchSettings, save: cam.save);
    await tester.pump();
    await tester.drag(find.byType(Slider), const Offset(400, 0));
    await tester.pumpAndSettle();
    expect(cam.posts, hasLength(1));
    expect(cam.posts.single['score'], 0.95);
    expect(find.text('A cat counts from 95 % certainty'), findsOneWidget);
  });

  testWidgets('the name is saved trimmed, and an empty one is not sent', (
    tester,
  ) async {
    final cam = _FakeCatCam();
    await _pump(tester, fetchSettings: cam.fetchSettings, save: cam.save);
    await tester.pump();
    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(cam.posts, isEmpty);
    await tester.enterText(find.byType(TextField), '  Cat Cam Küche ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(cam.posts.single, {'name': 'Cat Cam Küche'});
  });

  testWidgets('a refused change says so and shows what the cat cam kept', (
    tester,
  ) async {
    final cam = _FakeCatCam()..accept = false;
    await _pump(tester, fetchSettings: cam.fetchSettings, save: cam.save);
    await tester.pump();
    await tester.tap(find.byTooltip('Turn the picture right'));
    await tester.pumpAndSettle();
    expect(find.text('Could not save'), findsOneWidget);
    expect(find.text('270°'), findsOneWidget);
  });

  testWidgets('speaks German on the German page', (tester) async {
    final cam = _FakeCatCam();
    await _pump(
      tester,
      fetchSettings: cam.fetchSettings,
      locale: const Locale('de'),
    );
    await tester.pump();
    expect(find.text('Kamera-Einstellungen'), findsOneWidget);
    expect(find.text('Eine Katze zählt ab 45 % Sicherheit'), findsOneWidget);
    expect(find.textContaining('Katzenerkennung'), findsWidgets);
  });

  testWidgets('the preview reloads on its interval while the page shows', (
    tester,
  ) async {
    final cam = _FakeCatCam();
    await _pump(tester, fetchSettings: cam.fetchSettings);
    await tester.pump();
    final first =
        (tester.widget(find.byKey(const Key('preview'))) as Text).data;
    await tester.pump(const Duration(seconds: 3));
    final second =
        (tester.widget(find.byKey(const Key('preview'))) as Text).data;
    expect(second, isNot(first));
    await tester.pumpWidget(const SizedBox());
  });
}
