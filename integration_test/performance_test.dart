// Frame timings of the app's main paths, through Flutter's own tooling: run by flutter drive --profile and test_driver/perf_driver.dart.
import 'package:anthology/l10n/anthology_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:omni_accelerant/Pages/AiPlaygroundPage/ai_playground_controller.dart';
import 'package:omni_accelerant/Pages/AiPlaygroundPage/ai_playground_page.dart';
import 'package:omni_accelerant/Pages/AiPlaygroundPage/playground_settings.dart';
import 'package:omni_accelerant/Pages/AiPlaygroundPage/text_client.dart';
import 'package:omni_accelerant/l10n/app_localizations.dart';
import 'package:omni_accelerant/main.dart';
import 'package:omni_accelerant/src/rust/api/text.dart';
import 'package:omni_accelerant/src/rust/frb_generated.dart';

/// An answer with what the chat renders as Markdown: a heading, a list, code and a table.
const String _answer = """
## Two cats on the sofa

The camera saw **two cats** for 42 seconds:

- the grey one slept on the left cushion
- the black one *watched the window*
- neither went near the door

```text
visit 17:04:12 to 17:04:54, best score 0.91
```

| cat   | seconds | score |
| ----- | ------- | ----- |
| grey  | 42      | 0.91  |
| black | 38      | 0.87  |
""";

/// Streams [_answer] a few characters at a time with [interval] between pieces, as a decoding model does.
class _StreamingClient implements TextClient {
  Duration interval = Duration.zero;

  @override
  bool get localAvailable => true;

  @override
  Stream<TextEvent> generate(
    PlaygroundSettings settings,
    List<TextMessage> messages,
  ) async* {
    for (var start = 0; start < _answer.length; start += 4) {
      await Future<void>.delayed(interval);
      final end = start + 4 < _answer.length ? start + 4 : _answer.length;
      yield TextEvent(kind: 'piece', text: _answer.substring(start, end));
    }
    yield const TextEvent(kind: 'done', finishReason: 'stop');
  }

  @override
  void cancel() {}
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await RustLib.init();
  });

  testWidgets(
    'start, page switches and resizes stay within their frame budgets',
    (WidgetTester tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1100, 800);
      addTearDown(tester.view.reset);

      await binding.watchPerformance(() async {
        await tester.pumpWidget(const App());
        await tester.pumpAndSettle();
      }, reportKey: 'start');

      // Each tab in turn, three rounds: a page switch must not rebuild the app.
      Future<void> visit(IconData icon) async {
        await tester.tap(find.byIcon(icon).first);
        await tester.pumpAndSettle();
      }

      await binding.watchPerformance(() async {
        for (var round = 0; round < 3; round++) {
          await visit(Icons.tune_outlined);
          await visit(Icons.house_outlined);
          await visit(Icons.person_outlined);
          await visit(Icons.camera_enhance_outlined);
        }
      }, reportKey: 'page_switches');

      // Across both layout breakpoints and back, as a phone turns or a window is dragged.
      await binding.watchPerformance(() async {
        for (final width in <double>[800, 1200, 1600, 1250, 950, 600, 1100]) {
          tester.view.physicalSize = Size(width, 800);
          await tester.pumpAndSettle();
        }
      }, reportKey: 'resizes');
    },
  );

  // One AnimatedBuilder wraps the playground, so each piece rebuilds every visible answer's Markdown.
  testWidgets(
    'a streaming answer beside earlier ones stays within its frame budget',
    (WidgetTester tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1100, 1000);
      addTearDown(tester.view.reset);
      final client = _StreamingClient();
      final controller = AiPlaygroundController(client: client);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: <LocalizationsDelegate<dynamic>>[
            ...AppLocalizations.localizationsDelegates,
            AnthologyLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: AiPlaygroundView(controller: controller),
            ),
          ),
        ),
      );
      Future<void> ask(String question) async {
        controller.send(question);
        while (controller.busy) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.pumpAndSettle();
      }

      for (var earlier = 0; earlier < 3; earlier++) {
        await ask('What did the camera see, round $earlier?');
      }
      // About 60 pieces a second, a small model's decode rate on a desktop CPU.
      client.interval = const Duration(milliseconds: 16);
      await binding.watchPerformance(
        () => ask('And the last visit?'),
        reportKey: 'playground_streaming',
      );
      expect(controller.messages.last.text, _answer);
      expect(controller.messages.last.streaming, isFalse);
    },
  );
}
