// ObservANT's own answers of /settings, /visits, /ask and POST /summary, which `web.rs` writes and checks at the OxidANT pin.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_accelerant/Pages/CameraSettingsPage/camera_settings.dart';
import 'package:omni_accelerant/Pages/StreamPage/visit_questions.dart';
import 'package:omni_accelerant/Pages/StreamPage/visit_stats.dart';

/// The fixed arrival `web.rs` writes into the goldens: 2026-01-01 12:00 UTC.
const int _noon = 1767268800;

String _golden(String name) =>
    File('third_party/OxidANT/crates/observant/tests/fixtures/api/$name.json')
        .readAsStringSync();

void main() {
  test('/settings reads into the camera settings, every field', () {
    final settings = ObservantSettings.parse(_golden('settings'))!;
    expect(settings.name, 'Cam');
    expect(settings.rotate, 0);
    expect(settings.score, 0.25);
    expect(settings.ignore, isEmpty);
    expect(settings.classes, <String>['cat']);
    expect(settings.classesLocked, isFalse);
  });

  test('/visits reads into one finished stay', () {
    final stay = staysFromJson(_golden('visits')).single;
    expect(stay.arrived, DateTime.fromMillisecondsSinceEpoch(_noon * 1000));
    expect(stay.stayed, const Duration(seconds: 42));
  });

  test('/ask and POST /summary read into the answers and the facts', () async {
    final replies = <({int status, String body})?>[
      (status: 200, body: _golden('ask')),
      (status: 200, body: _golden('summary_words')),
    ];
    final controller = VisitQuestionsController(
      post: (path, body, {cancel}) async => replies.removeAt(0),
      language: 'en',
      now: () => DateTime.fromMillisecondsSinceEpoch(_noon * 1000),
    );
    await controller.ask('How often?');
    expect(controller.facts, '<the facts the model was given>');
    await controller.summarise('Summarise today', 'No visits today.');
    expect(controller.messages.map((m) => m.text), <String>[
      'How often?',
      'Twice.',
      'Summarise today',
      'Twice.',
    ]);
    expect(controller.failure, isNull);
  });
}
