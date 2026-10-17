import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_accelerant/Pages/CameraSettingsPage/camera_settings.dart';
import 'package:omni_accelerant/l10n/app_localizations.dart';

const _healthz =
    '{"ok":true,"name":"Cat Cam Futtertrog","rotate":270,"score":0.45,'
    '"frame":{"width":640,"height":480,"fps":15},"camera":"imx708",'
    '"inference":true,"model_runs":1234,"cat":{"visits":7,"last_score":0.3354}}';

/// An ObservANT camera that keeps what the page posts, as `/settings` does.
class _FakeObservant {
  Map<String, Object> settings = {
    'name': 'Cat Cam Futtertrog',
    'rotate': 270,
    'score': 0.45,
  };
  final posts = <Map<String, Object>>[];
  bool accept = true;

  /// Restarting, say after an upgrade: nothing answers.
  bool down = false;

  Future<String?> fetchSettings() async => down ? null : jsonEncode(settings);

  Future<String?> fetchHealthz() async => down ? null : _healthz;

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

Widget _fakeDetection(String url) => Text('detection $url');

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
            detectionPicture: _fakeDetection,
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('ObservantSettings.parse', () {
    test('reads name, rotation and score', () {
      final settings = ObservantSettings.parse(
        '{"name":"Büro","rotate":90,"score":0.5}',
      )!;
      expect(settings.name, 'Büro');
      expect(settings.rotate, 90);
      expect(settings.score, 0.5);
    });

    test('takes a whole-number score', () {
      expect(
        ObservantSettings.parse('{"name":"a","rotate":0,"score":1}')!.score,
        1.0,
      );
    });

    test('is null for anything but an ObservANT camera answer', () {
      for (final body in <String?>[
        null,
        'not json',
        '[1, 2]',
        '{"name":"a","rotate":"90","score":0.5}',
        '{"rotate":90,"score":0.5}',
        '<!doctype html>',
      ]) {
        expect(ObservantSettings.parse(body), isNull, reason: body);
      }
    });
  });

  group('ObservantInfo.parse', () {
    test('reads the camera, its frame and what the model did', () {
      final info = ObservantInfo.parse(_healthz)!;
      expect(info.camera, 'imx708');
      expect((info.width, info.height, info.fps), (640, 480, 15));
      expect(info.inference, isTrue);
      expect(info.modelRuns, 1234);
      expect(info.visits, 7);
      expect(info.lastScore, closeTo(0.3354, 1e-9));
    });

    test('an older ObservANT without a frame block still parses', () {
      final info = ObservantInfo.parse('{"ok":true,"camera":"x"}')!;
      expect(info.width, isNull);
      expect(info.modelRuns, 0);
      expect(info.lastScore, isNull);
    });

    test('is null without ok, or for garbage', () {
      expect(ObservantInfo.parse('{"camera":"x"}'), isNull);
      expect(ObservantInfo.parse('nope'), isNull);
      expect(ObservantInfo.parse(null), isNull);
    });

    test('a camera that is not ok still parses, with its problem', () {
      final info = ObservantInfo.parse(
        '{"ok":false,"problem":"no frame for 45 s","camera":"x"}',
      )!;
      expect(info.problem, 'no frame for 45 s');
      expect(ObservantInfo.parse(_healthz)!.problem, isNull);
    });

    test('carries the build ObservANT names', () {
      final info = ObservantInfo.parse(
        _healthz.replaceFirst(
          '"ok":true',
          '"ok":true,"version":"2.0.0 (481ad36)"',
        ),
      )!;
      expect(info.version, '2.0.0 (481ad36)');
      expect(ObservantInfo.parse(_healthz)!.version, isEmpty);
    });

    test('knows whether the privacy filter is on', () {
      final info = ObservantInfo.parse(
        _healthz.replaceFirst('"ok":true', '"ok":true,"privacy":"pixelate"'),
      )!;
      expect(info.pixelated, isTrue);
      expect(ObservantInfo.parse(_healthz)!.pixelated, isFalse);
    });
  });

  testWidgets(
    'without an ObservANT camera the page says so and offers nothing to change',
    (tester) async {
      await _pump(tester, fetchSettings: () async => null);
      await tester.pump();
      expect(
        find.textContaining('No ObservANT camera answers here'),
        findsOneWidget,
      );
      expect(find.byType(Slider), findsNothing);
      expect(find.byKey(const Key('preview')), findsNothing);
    },
  );

  testWidgets(
    'a camera that goes away keeps its settings shown and is picked up again',
    (tester) async {
      final cam = _FakeObservant();
      await _pump(
        tester,
        fetchSettings: cam.fetchSettings,
        fetchHealthz: cam.fetchHealthz,
        save: cam.save,
      );
      await tester.pump();
      expect(find.byType(Slider), findsOneWidget);

      cam.down = true;
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(find.byKey(const ValueKey('camera-lost')), findsOneWidget);
      expect(find.textContaining('unreachable since'), findsOneWidget);
      expect(
        find.byType(Slider),
        findsOneWidget,
        reason: 'its last answer stays',
      );

      cam.down = false;
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(find.byKey(const ValueKey('camera-lost')), findsNothing);
      expect(find.byType(Slider), findsOneWidget);
    },
  );

  testWidgets(
    'a camera down at the first look is asked again, by itself or the button',
    (tester) async {
      final cam = _FakeObservant()..down = true;
      await _pump(
        tester,
        fetchSettings: cam.fetchSettings,
        fetchHealthz: cam.fetchHealthz,
      );
      await tester.pump();
      expect(find.text('Try again'), findsOneWidget);

      cam.down = false;
      await tester.tap(find.text('Try again'));
      await tester.pump();
      await tester.pump();
      expect(find.byType(Slider), findsOneWidget);

      // And without the button: the next tick asks again.
      await tester.pumpWidget(const SizedBox());
      cam.down = true;
      await _pump(
        tester,
        fetchSettings: cam.fetchSettings,
        fetchHealthz: cam.fetchHealthz,
      );
      await tester.pump();
      cam.down = false;
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(find.byType(Slider), findsOneWidget);
    },
  );

  testWidgets('a failing fetch reads as no ObservANT, not as an error', (
    tester,
  ) async {
    await _pump(
      tester,
      fetchSettings: () async => throw StateError('offline'),
      fetchHealthz: () async => throw StateError('offline'),
    );
    await tester.pump();
    expect(
      find.textContaining('No ObservANT camera answers here'),
      findsOneWidget,
    );
  });

  testWidgets('shows the preview, the settings and the camera info', (
    tester,
  ) async {
    final cam = _FakeObservant();
    await _pump(tester, fetchSettings: cam.fetchSettings, save: cam.save);
    await tester.pump();
    expect(find.text('Camera settings'), findsOneWidget);
    expect(find.textContaining('preview /snapshot.jpg'), findsOneWidget);
    expect(find.text('270°'), findsOneWidget);
    expect(find.text('A detection counts from 45 % certainty'), findsOneWidget);
    expect(
      find.widgetWithText(TextField, 'Cat Cam Futtertrog'),
      findsOneWidget,
    );
    expect(find.textContaining('640 × 480'), findsOneWidget);
    expect(find.textContaining('15 fps'), findsOneWidget);
    expect(find.textContaining('imx708'), findsOneWidget);
    expect(find.textContaining('1234'), findsOneWidget);
    // Where a false arrival sits, so the slider can go just above it.
    expect(find.text('Last detection: 34 %'), findsOneWidget);
  });

  testWidgets('the rotate buttons turn the picture a quarter each way', (
    tester,
  ) async {
    final cam = _FakeObservant();
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
    final cam = _FakeObservant();
    await _pump(tester, fetchSettings: cam.fetchSettings, save: cam.save);
    await tester.pump();
    await tester.drag(find.byType(Slider), const Offset(400, 0));
    await tester.pumpAndSettle();
    expect(cam.posts, hasLength(1));
    expect(cam.posts.single['score'], 0.95);
    expect(find.text('A detection counts from 95 % certainty'), findsOneWidget);
  });

  testWidgets('the name is saved trimmed, and an empty one is not sent', (
    tester,
  ) async {
    final cam = _FakeObservant();
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

  testWidgets('a refused change says so and shows what ObservANT kept', (
    tester,
  ) async {
    final cam = _FakeObservant()..accept = false;
    await _pump(tester, fetchSettings: cam.fetchSettings, save: cam.save);
    await tester.pump();
    await tester.tap(find.byTooltip('Turn the picture right'));
    await tester.pumpAndSettle();
    expect(find.text('Could not save'), findsOneWidget);
    expect(find.text('270°'), findsOneWidget);
  });

  testWidgets('speaks German on the German page', (tester) async {
    final cam = _FakeObservant();
    await _pump(
      tester,
      fetchSettings: cam.fetchSettings,
      locale: const Locale('de'),
    );
    await tester.pump();
    expect(find.text('Kamera-Einstellungen'), findsOneWidget);
    expect(
      find.text('Eine Erkennung zählt ab 45 % Sicherheit'),
      findsOneWidget,
    );
    expect(find.text('Letzte Erkennung: 34 %'), findsOneWidget);
    expect(find.textContaining('Erkennung'), findsWidgets);
  });

  testWidgets(
    'a page behind another tab fetches nothing, and reads the camera again on return',
    (tester) async {
      final cam = _FakeObservant();
      var fetches = 0;
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
                  child: SingleChildScrollView(
                    child: CameraSettingsPanel(
                      fetchSettings: () {
                        fetches++;
                        return cam.fetchSettings();
                      },
                      saveSettings: cam.save,
                      fetchHealthz: () async => _healthz,
                      preview: _fakePreview,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();
      String preview() =>
          (tester.widget(find.byKey(const Key('preview'))) as Text).data!;
      flip(() => shown = false);
      await tester.pump();
      final hidden = preview();
      await tester.pump(const Duration(seconds: 10));
      expect(preview(), hidden, reason: 'no snapshot while hidden');
      expect(fetches, 1);
      cam.settings = {...cam.settings, 'rotate': 90};
      flip(() => shown = true);
      await tester.pump();
      await tester.pump();
      expect(fetches, 2);
      expect(find.text('90°'), findsOneWidget);
      expect(preview(), isNot(hidden));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('the preview reloads on its interval while the page shows', (
    tester,
  ) async {
    final cam = _FakeObservant();
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

  group('zones', () {
    test('parse from [x1, y1, x2, y2] lists and skip anything else', () {
      expect(
        parseZones([
          [0.25, 0.75, 0.75, 1],
          [0.5, 0.5, 0.4, 0.9],
          [0, 0, 1],
          'x',
        ]),
        [const Rect.fromLTRB(0.25, 0.75, 0.75, 1)],
      );
      expect(parseZones(null), isEmpty);
      expect(zoneJson(const Rect.fromLTRB(0.12345, 0.2, 0.3, 0.4)), [
        0.123,
        0.2,
        0.3,
        0.4,
      ]);
    });

    test('come from /settings and /healthz, empty from an older ObservANT', () {
      final settings = ObservantSettings.parse(
        '{"name":"x","rotate":0,"score":0.3,"ignore":[[0.1,0.2,0.3,0.4]]}',
      )!;
      expect(settings.ignore, [const Rect.fromLTRB(0.1, 0.2, 0.3, 0.4)]);
      expect(
        ObservantSettings.parse('{"name":"x","rotate":0,"score":0.3}')!.ignore,
        isEmpty,
      );
      final info = ObservantInfo.parse(
        _healthz.replaceFirst(
          '"visits":7',
          '"visits":7,"boxes":[[0,0,0.5,0.5]]',
        ),
      )!;
      expect(info.boxes, [const Rect.fromLTRB(0, 0, 0.5, 0.5)]);
      expect(ObservantInfo.parse(_healthz)!.boxes, isEmpty);
    });
  });

  testWidgets('"False alarm" adds the boxes shown to the ignored spots', (
    tester,
  ) async {
    final cam = _FakeObservant()
      ..settings['ignore'] = [
        [0.0, 0.0, 0.1, 0.1],
      ];
    var healthz = _healthz;
    await _pump(
      tester,
      fetchSettings: cam.fetchSettings,
      save: cam.save,
      fetchHealthz: () async => healthz,
    );
    await tester.pump();
    expect(find.text('False alarm'), findsNothing);
    expect(
      find.text('1 spot is ignored (grey on the preview)'),
      findsOneWidget,
    );
    // The drying rack is boxed now: the next preview tick reads it from /healthz.
    healthz = _healthz.replaceFirst(
      '"visits":7',
      '"visits":7,"boxes":[[0.25,0.75,0.75,1.0]]',
    );
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    await tester.tap(find.text('False alarm'));
    await tester.pump();
    expect(cam.posts.last, {
      'ignore': [
        [0.0, 0.0, 0.1, 0.1],
        [0.25, 0.75, 0.75, 1.0],
      ],
    });
    await tester.pump();
    expect(
      find.text('2 spots are ignored (grey on the preview)'),
      findsOneWidget,
    );
    await tester.tap(find.text('Watch again'));
    await tester.pump();
    expect(cam.posts.last, {'ignore': <List<double>>[]});
    await tester.pump();
    expect(find.textContaining('ignored'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('speaks German about ignored spots', (tester) async {
    final cam = _FakeObservant()
      ..settings['ignore'] = [
        [0.0, 0.0, 0.1, 0.1],
        [0.2, 0.2, 0.3, 0.3],
      ];
    await _pump(
      tester,
      fetchSettings: cam.fetchSettings,
      fetchHealthz: () async => _healthz.replaceFirst(
        '"visits":7',
        '"visits":7,"boxes":[[0.25,0.75,0.75,1.0]]',
      ),
      locale: const Locale('de'),
    );
    await tester.pump();
    expect(find.text('Fehlalarm'), findsOneWidget);
    expect(
      find.text('2 Stellen werden ignoriert (grau in der Vorschau)'),
      findsOneWidget,
    );
    expect(find.text('Wieder beachten'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  test('recent detections come from the visits that kept boxes, five at most', () {
    final visits = [
      for (var i = 0; i < 7; i++)
        '{"arrived":${1791900000 - i * 600},"stayed_s":30,"boxes":[[0.25,0.75,0.75,1.0]]}',
      '{"arrived":1791000000,"stayed_s":30}',
    ].join(',');
    final info = ObservantInfo.parse(
      _healthz.replaceFirst('"visits":7', '"visits":7,"recent":[$visits]'),
    )!;
    expect(info.detections, hasLength(5));
    expect(
      info.detections.first.arrived.millisecondsSinceEpoch,
      1791900000 * 1000,
    );
    expect(info.detections.first.boxes, [
      const Rect.fromLTRB(0.25, 0.75, 1 - 0.25, 1),
    ]);
    expect(ObservantInfo.parse(_healthz)!.detections, isEmpty);
  });

  testWidgets(
    'a recent detection marked "not a cat" adds its boxes and then reads as ignored',
    (tester) async {
      final cam = _FakeObservant()..settings['ignore'] = <List<double>>[];
      const rack = '[[0.25,0.75,0.75,1.0]]';
      final healthz = _healthz.replaceFirst(
        '"visits":7',
        '"visits":7,"recent":[{"arrived":1791900000,"stayed_s":172,"boxes":$rack}]',
      );
      await _pump(
        tester,
        fetchSettings: cam.fetchSettings,
        save: cam.save,
        fetchHealthz: () async => healthz,
      );
      await tester.pump();
      expect(find.text('Recent detections'), findsOneWidget);
      expect(find.text('detection /arrival.jpg?t=1791900000'), findsOneWidget);
      await tester.ensureVisible(find.text('False alarm').last);
      await tester.tap(find.text('False alarm').last);
      await tester.pump();
      expect(cam.posts.last, {
        'ignore': [
          [0.25, 0.75, 0.75, 1.0],
        ],
      });
      await tester.pump();
      expect(find.text('Ignored'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'reads the watched classes, and none from an ObservANT camera before them',
    () {
      expect(
        ObservantSettings.parse(
          '{"name":"A","rotate":0,"score":0.3,"classes":["cat","dog"]}',
        )!.classes,
        ['cat', 'dog'],
      );
      expect(
        ObservantSettings.parse('{"name":"A","rotate":0,"score":0.3}')!.classes,
        isNull,
      );
      expect(
        ObservantSettings.parse(
          '{"name":"A","rotate":0,"score":0.3,"privacy":"pixelate"}',
        )!.classesLocked,
        isTrue,
      );
      expect(
        ObservantSettings.parse(
          '{"name":"A","rotate":0,"score":0.3,"privacy":"off"}',
        )!.classesLocked,
        isFalse,
      );
    },
  );

  testWidgets('a class is added from the menu and removed by its chip', (
    tester,
  ) async {
    final cam = _FakeObservant()
      ..settings = {
        'name': 'Cat Cam Futtertrog',
        'rotate': 270,
        'score': 0.45,
        'classes': ['cat'],
      };
    await _pump(tester, fetchSettings: cam.fetchSettings, save: cam.save);
    await tester.pump();
    expect(find.text('What it detects'), findsOneWidget);
    // The only class cannot go: an ObservANT camera always watches something.
    final onlyChip = tester.widget<InputChip>(find.byType(InputChip));
    expect(onlyChip.onDeleted, isNull);

    await tester.ensureVisible(find.byKey(const ValueKey('add-class')));
    await tester.tap(find.byKey(const ValueKey('add-class')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('add-class')), 'dog');
    await tester.pumpAndSettle();
    await tester.tap(find.text('dog').last);
    await tester.pumpAndSettle();
    expect(cam.posts.last, {
      'classes': ['cat', 'dog'],
    });
    expect(find.widgetWithText(InputChip, 'dog'), findsOneWidget);

    tester
        .widget<InputChip>(find.widgetWithText(InputChip, 'cat'))
        .onDeleted!();
    await tester.pumpAndSettle();
    expect(cam.posts.last, {
      'classes': ['dog'],
    });
    expect(find.widgetWithText(InputChip, 'cat'), findsNothing);
  });

  testWidgets(
    'with the privacy filter on, the classes show but no page changes them',
    (tester) async {
      final cam = _FakeObservant()
        ..settings = {
          'name': 'Cat Cam Futtertrog',
          'rotate': 270,
          'score': 0.45,
          'classes': ['cat', 'dog'],
          'privacy': 'pixelate',
        };
      await _pump(tester, fetchSettings: cam.fetchSettings, save: cam.save);
      await tester.pump();
      expect(find.widgetWithText(InputChip, 'dog'), findsOneWidget);
      for (final chip in tester.widgetList<InputChip>(find.byType(InputChip))) {
        expect(chip.onDeleted, isNull);
      }
      expect(find.byKey(const ValueKey('add-class')), findsNothing);
      expect(find.textContaining('observant.toml'), findsOneWidget);
      expect(cam.posts, isEmpty);
    },
  );

  testWidgets(
    'an ObservANT camera that cannot change its classes shows no editor',
    (tester) async {
      final cam = _FakeObservant();
      await _pump(tester, fetchSettings: cam.fetchSettings, save: cam.save);
      await tester.pump();
      expect(find.text('What it detects'), findsNothing);
      expect(find.byType(InputChip), findsNothing);
    },
  );
}
