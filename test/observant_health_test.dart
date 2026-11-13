import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_accelerant/Pages/CameraSettingsPage/camera_settings.dart';
import 'package:omni_accelerant/Pages/StreamPage/detection_status.dart';
import 'package:omni_accelerant/Pages/StreamPage/dev_stats.dart';
import 'package:omni_accelerant/Pages/StreamPage/observant_health.dart';
import 'package:omni_accelerant/Pages/StreamPage/poll_gate.dart';

/// What `kataglyphis_observant --camera test` (OxidANT 7abcc12, with its model) answered on `/healthz`, unchanged.
final String _idle = File('test/fixtures/observant_healthz_idle.json')
    .readAsStringSync();

/// The idle answer with a visit in it, in the keys `status.rs` writes; hand-filled, no camera saw this cat.
String _visited() {
  final json = jsonDecode(_idle) as Map<String, dynamic>;
  json['detection'] = <String, Object?>{
    'boxes': [
      [0.25, 0.25, 0.75, 0.75],
    ],
    'clip': 1791763200,
    'clips': [1791763200, 1791700000],
    'in_view': true,
    'last_score': 0.61,
    'last_seen': 1791763273,
    'recent': [
      {
        'arrived': 1791763200,
        'stayed_s': null,
        'class': 'cat',
        'boxes': [
          [0.1, 0.2, 0.3, 0.4],
        ],
      },
      {'arrived': 1791700000, 'stayed_s': 20, 'class': 'dog'},
    ],
    'visits': 2,
  };
  json
    ..['ask'] = true
    ..['privacy'] = 'pixelate'
    ..['rotate'] = 90
    ..['peers'] = ['http://192.168.1.21:8080']
    ..['viewers'] = 2;
  return jsonEncode(json);
}

DateTime _at(int seconds) =>
    DateTime.fromMillisecondsSinceEpoch(seconds * 1000);

void main() {
  group('ObservantHealth', () {
    test('reads every field of a real idle answer', () {
      final health = ObservantHealth.parse(_idle)!;
      expect(health.ok, isTrue);
      expect(health.problem, isNull);
      expect(health.name, '80e2b23d47d9');
      expect(health.camera, 'test pattern');
      expect(health.version, '3.0.0-dev');
      expect(health.classes, ['cat']);
      expect(
        (health.dark, health.pixelated, health.inference),
        (false, false, true),
      );
      expect(health.answersQuestions, isFalse);
      expect((health.rotate, health.viewers, health.modelRuns), (0, 0, 8));
      expect(health.peers, isEmpty);
      expect(
        (health.frameWidth, health.frameHeight, health.frameFps),
        (640, 480, 30),
      );
      expect(health.hasStats, isTrue);
      expect(health.stat('capture_fps'), 30.0);
      expect(health.stat('model_ms'), 292.5);
      expect(health.wholeStat('cores'), 4);
      expect(health.wholeStat('uptime_s'), 4);
      expect(health.hasDetection, isTrue);
      expect((health.inView, health.visits), (false, 0));
      expect(health.lastSeen, isNull);
      expect(health.recent, isEmpty);
    });

    test('reads a visit, its clips and its boxes', () {
      final health = ObservantHealth.parse(_visited())!;
      expect((health.inView, health.visits), (true, 2));
      expect(health.lastSeen, _at(1791763273));
      expect(health.lastScore, 0.61);
      expect(health.clip, _at(1791763200));
      expect(health.clips, [_at(1791763200), _at(1791700000)]);
      expect(health.recent.map((v) => (v.arrived, v.stayed, v.className)), [
        (_at(1791763200), null, 'cat'),
        (_at(1791700000), const Duration(seconds: 20), 'dog'),
      ]);
      expect(health.boxes, isNotNull);
      expect((health.pixelated, health.answersQuestions), (true, true));
      expect((health.rotate, health.viewers), (90, 2));
      expect(health.peers, ['http://192.168.1.21:8080']);
    });

    test('is null for anything but an ObservANT answer', () {
      for (final body in <String?>[
        null,
        '',
        'not json',
        '[]',
        '{"name":"x"}',
        '{"ok":"yes"}',
      ]) {
        expect(ObservantHealth.parse(body), isNull, reason: '$body');
      }
    });

    test('says why a camera is not ok, and nothing while it is', () {
      expect(
        ObservantHealth.parse(
          '{"ok":false,"problem":"the model has not answered for 21 s"}',
        )!.problem,
        'the model has not answered for 21 s',
      );
      expect(ObservantHealth.parse('{"ok":false}')!.problem, '');
      expect(
        ObservantHealth.parse('{"ok":true,"problem":"x"}')!.problem,
        isNull,
      );
    });

    test('still reads a camera from before ObservANT, which wrote `cat`', () {
      final old = ObservantHealth.parse(
        '{"ok":true,"cat":{"in_view":true,"visits":3}}',
      )!;
      expect((old.inView, old.visits), (true, 3));
      expect(old.classes, isNull);
      expect(old.rotate, isNull);
      expect(ObservantHealth.parse('{"ok":true,"rotate":45}')!.rotate, isNull);
    });
  });

  group('the page parts on a real answer', () {
    test('the status line, the stats and the settings find their fields', () {
      final status = DetectionStatus.fromHealthz(_visited())!;
      expect(status.name, '80e2b23d47d9');
      expect((status.inView, status.visits, status.pixelated), (true, 2, true));
      expect(status.rotate, 90);
      expect(status.recent.length, 2);
      expect(status.hasLatestClip, isTrue);
      expect(DetectionStatus.fromHealthz(_idle)!.classes, ['cat']);

      final stats = ServerStats.fromHealthz(_idle)!;
      expect(
        [
          stats.captureFps,
          stats.configuredFps,
          stats.modelMs,
          stats.modelRunsPerSecond,
          stats.cpuPercent,
          stats.cores,
          stats.rssMb,
          stats.load1m,
          stats.temperatureC,
          stats.uptime,
          stats.viewers,
        ],
        everyElement(isNotNull),
        reason: 'a key ObservANT renamed leaves its number empty',
      );

      final info = ObservantInfo.parse(_visited())!;
      expect((info.camera, info.version), ('test pattern', '3.0.0-dev'));
      expect((info.width, info.height, info.fps), (640, 480, 30));
      expect((info.inference, info.modelRuns, info.visits), (true, 8, 2));
      expect(info.boxes.length, 1);
      expect(info.detections.length, 1, reason: 'only arrivals with boxes');
      expect(info.lastScore, 0.61);
    });

    test('an answer without stats or without detection is none of theirs', () {
      expect(ServerStats.fromHealthz('{"ok":true}'), isNull);
      expect(DetectionStatus.fromHealthz('{"ok":true}'), isNull);
      expect(ObservantInfo.parse('{"ok":true}')!.visits, 0);
    });
  });

  test('`/healthz` is read by key in one file only', () {
    final readers = <String>[
      for (final file in Directory('lib').listSync(recursive: true))
        if (file is File && file.path.endsWith('.dart'))
          if (RegExp(r"\w\[\s*'(detection|cat|stats|model_runs)'\s*\]")
              .hasMatch(file.readAsStringSync()))
            file.path.replaceAll(r'\', '/'),
    ];
    expect(readers, ['lib/Pages/StreamPage/observant_health.dart']);
  });

  group('PollGate', () {
    test('drops a poll while the one before still waits', () async {
      final gate = PollGate();
      final answers = <Completer<void>>[];
      Future<void> poll() {
        answers.add(Completer<void>());
        return answers.last.future;
      }

      for (var tick = 0; tick < 5; tick++) {
        unawaited(gate.run(poll));
        await Future<void>.delayed(Duration.zero);
      }
      expect(answers.length, 1);
      answers.single.complete();
      await Future<void>.delayed(Duration.zero);
      unawaited(gate.run(poll));
      expect(answers.length, 2);
      answers.last.complete();
    });

    test('opens again after a poll that failed', () async {
      final gate = PollGate();
      var polls = 0;
      await expectLater(
        gate.run(() async {
          polls++;
          throw StateError('offline');
        }),
        throwsStateError,
      );
      await gate.run(() async => polls++);
      expect(polls, 2);
    });
  });
}
