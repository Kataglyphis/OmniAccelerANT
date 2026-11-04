// The Stream page's questions against a fake ObservANT; the HTTP half is `observant_api_web_test.dart`.
import 'dart:async';
import 'dart:convert';

import 'package:anthology/l10n/anthology_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_accelerant/Pages/StreamPage/visit_questions.dart';
import 'package:omni_accelerant/l10n/app_localizations.dart';

typedef _Reply = ({int status, String body});

/// Records what the panel posted and answers from [replies] in turn.
class _Camera {
  _Camera(this.replies);

  final List<_Reply?> replies;
  final List<(String, Map<String, Object>)> posted =
      <(String, Map<String, Object>)>[];
  Completer<_Reply?>? held;
  Future<void>? lastCancel;

  Future<_Reply?> post(
    String path,
    Map<String, Object> body, {
    Future<void>? cancel,
  }) {
    posted.add((path, body));
    lastCancel = cancel;
    final waiting = held;
    return waiting != null
        ? waiting.future
        : Future<_Reply?>.value(replies.removeAt(0));
  }
}

_Reply _answer(String answer, String facts) => (
  status: 200,
  body: jsonEncode(<String, Object>{'answer': answer, 'facts': facts}),
);

final DateTime _now = DateTime(2026, 11, 4, 12);

VisitQuestionsController _controller(
  _Camera camera, {
  String language = 'en',
}) => VisitQuestionsController(
  post: camera.post,
  language: language,
  now: () => _now,
);

Future<void> _pump(
  WidgetTester tester,
  _Camera camera, {
  String? health = '{"ask":true}',
}) => tester.pumpWidget(
  MaterialApp(
    localizationsDelegates: const [
      ...AppLocalizations.localizationsDelegates,
      AnthologyLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: Scaffold(
      body: SingleChildScrollView(
        child: VisitQuestionsPanel(
          fetchHealth: () async => health,
          post: camera.post,
          now: () => _now,
        ),
      ),
    ),
  ),
);

void main() {
  group('VisitQuestionsController', () {
    test(
      'a question reaches /ask with the local offset and language',
      () async {
        final camera = _Camera(<_Reply?>[_answer('Twice.', '2 visits')]);
        final controller = _controller(camera, language: 'de');
        await controller.ask('How often?');
        final (path, body) = camera.posted.single;
        expect(path, '/ask');
        expect(body['question'], 'How often?');
        expect(body['tz_offset_min'], _now.timeZoneOffset.inMinutes);
        expect(body['language'], 'de');
        expect(controller.messages.map((m) => m.text), <String>[
          'How often?',
          'Twice.',
        ]);
        expect(controller.facts, '2 visits');
        expect(controller.failure, isNull);
        expect(controller.busy, isFalse);
      },
    );

    test('a language ObservANT does not take is left out', () async {
      final camera = _Camera(<_Reply?>[_answer('Yes.', 'f')]);
      await _controller(camera, language: 'fr').ask('Oui?');
      expect(camera.posted.single.$2.containsKey('language'), isFalse);
    });

    test('a refusal shows the camera\'s own words and no answer', () async {
      final camera = _Camera(<_Reply?>[
        (status: 502, body: 'generation failed: out of memory'),
      ]);
      final controller = _controller(camera);
      await controller.ask('How often?');
      expect(controller.failure?.reason, contains('out of memory'));
      expect(controller.messages.map((m) => m.text), <String>['How often?']);
    });

    test('no reply is its own failure', () async {
      final controller = _controller(_Camera(<_Reply?>[null]));
      await controller.ask('How often?');
      expect(controller.failure, isNotNull);
      expect(controller.failure?.reason, isNull);
    });

    test(
      'an answer that is no answer is a failure, not an empty message',
      () async {
        for (final body in <String>['not json', '{"answer":5}', '[]']) {
          final camera = _Camera(<_Reply?>[(status: 200, body: body)]);
          final controller = _controller(camera);
          await controller.ask('How often?');
          expect(controller.failure?.reason, body);
          expect(controller.messages, hasLength(1));
        }
      },
    );

    test(
      'a summary posts to /summary and an empty day reads as none',
      () async {
        final camera = _Camera(<_Reply?>[
          (status: 200, body: '{"visits":2,"summary":"Two short visits."}'),
          (status: 200, body: '{"visits":0,"summary":null}'),
        ]);
        final controller = _controller(camera);
        await controller.summarise('Summarise today', 'No visits today.');
        await controller.summarise('Summarise today', 'No visits today.');
        expect(camera.posted.first.$1, '/summary');
        expect(camera.posted.first.$2.containsKey('question'), isFalse);
        expect(controller.messages.map((m) => m.text), <String>[
          'Summarise today',
          'Two short visits.',
          'Summarise today',
          'No visits today.',
        ]);
      },
    );

    test('one question at a time, and stop leaves the running one', () async {
      final camera = _Camera(<_Reply?>[])..held = Completer<_Reply?>();
      final controller = _controller(camera);
      final first = controller.ask('one');
      expect(controller.busy, isTrue);
      expect(controller.messages.last.streaming, isTrue);
      await controller.ask('two');
      expect(camera.posted, hasLength(1));
      var cancelled = false;
      unawaited(camera.lastCancel!.then((_) => cancelled = true));
      controller.stop();
      await Future<void>.delayed(Duration.zero);
      expect(cancelled, isTrue);
      camera.held!.complete(null);
      await first;
      expect(controller.busy, isFalse);
      expect(controller.failure, isNull);
      expect(controller.messages.map((m) => m.text), <String>['one']);
      controller.stop();
    });
  });

  group('VisitQuestionsPanel', () {
    for (final (name, health) in <(String, String?)>[
      ('says no model answers', '{"ask":false}'),
      ('predates questions', '{"ok":true}'),
      ('does not answer', null),
    ]) {
      testWidgets('offers nothing when the camera $name', (tester) async {
        await _pump(tester, _Camera(<_Reply?>[]), health: health);
        await tester.pumpAndSettle();
        expect(find.text('Ask about the visits'), findsNothing);
      });
    }

    testWidgets('asks, answers and shows what the model was told', (
      tester,
    ) async {
      final camera = _Camera(<_Reply?>[_answer('Twice.', 'Two visits today.')]);
      await _pump(tester, camera);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ask about the visits'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('A language model can be wrong'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField), 'How often?');
      await tester.pump();
      await tester.tap(find.byTooltip('Send'));
      await tester.pumpAndSettle();
      expect(camera.posted.single.$1, '/ask');
      expect(find.text('Twice.', findRichText: true), findsOneWidget);
      await tester.tap(find.text('What the model was told'));
      await tester.pumpAndSettle();
      expect(find.text('Two visits today.'), findsOneWidget);
    });

    testWidgets('shows the camera\'s refusal', (tester) async {
      final camera = _Camera(<_Reply?>[
        (status: 503, body: 'still answering another question'),
      ]);
      await _pump(tester, camera);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ask about the visits'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Summarise today'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('still answering another question'),
        findsOneWidget,
      );
    });
  });
}
