// The AI Playground against a fake backend, and its bridge client against a mocked Rust core.
@TestOn('vm')
library;

import 'dart:async';

import 'package:anthology/Widgets/Chat/chat_entry.dart';
import 'package:anthology/l10n/anthology_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_accelerant/Pages/AiPlaygroundPage/ai_playground_controller.dart';
import 'package:omni_accelerant/Pages/AiPlaygroundPage/ai_playground_page.dart';
import 'package:omni_accelerant/Pages/AiPlaygroundPage/playground_settings.dart';
import 'package:omni_accelerant/Pages/AiPlaygroundPage/text_client.dart';
import 'package:omni_accelerant/l10n/app_localizations.dart';
import 'package:omni_accelerant/src/rust/api/text.dart';
import 'package:omni_accelerant/src/rust/frb_generated.dart';

const TextEvent _done = TextEvent(
  kind: 'done',
  finishReason: 'stop',
  promptTokens: 9,
  completionTokens: 3,
  timeToFirstTokenMs: 40,
  decodeTokensPerSecond: 150,
);

/// Answers every message with the pieces it holds, recording what it was asked.
class _FakeClient implements TextClient {
  final List<List<TextMessage>> asked = <List<TextMessage>>[];
  StreamController<TextEvent>? running;
  int cancels = 0;

  @override
  bool get localAvailable => false;

  @override
  Stream<TextEvent> generate(
    PlaygroundSettings settings,
    List<TextMessage> messages,
  ) {
    asked.add(messages);
    running = StreamController<TextEvent>();
    return running!.stream;
  }

  @override
  void cancel() => cancels++;

  void answer(List<String> pieces, [TextEvent done = _done]) {
    for (final piece in pieces) {
      running!.add(TextEvent(kind: 'piece', text: piece));
    }
    running!
      ..add(done)
      ..close();
  }
}

/// The Rust core, recording the text calls the client makes.
class _FakeRustApi extends Fake implements RustLibApi {
  TextSource? source;
  List<TextMessage>? messages;
  TextOptions? options;
  int cancels = 0;

  @override
  bool crateApiTextTextLocalAvailable() => true;

  @override
  Stream<TextEvent> crateApiTextTextGenerate({
    required TextSource source,
    required List<TextMessage> messages,
    required TextOptions options,
  }) {
    this.source = source;
    this.messages = messages;
    this.options = options;
    return Stream<TextEvent>.fromIterable(<TextEvent>[_done]);
  }

  @override
  void crateApiTextTextCancel() => cancels++;
}

void main() {
  final rust = _FakeRustApi();
  setUpAll(() => RustLib.initMock(api: rust));

  test(
    'an answer streams into the conversation and ends with its figures',
    () async {
      final client = _FakeClient();
      final playground = AiPlaygroundController(client: client);
      playground.send('Capital of France?');
      expect(playground.busy, isTrue);
      expect(playground.messages.last.streaming, isTrue);
      client.answer(<String>['The capital', ' is Paris.']);
      await pumpEventQueue();
      final answer = playground.messages.last;
      expect(answer.text, 'The capital is Paris.');
      expect(answer.streaming, isFalse);
      expect(answer.figures!.completionTokens, 3);
      expect(answer.figures!.finish, ChatFinish.stop);
      expect(playground.busy, isFalse);
    },
  );

  test(
    'each message carries the system prompt and the conversation before it',
    () async {
      final client = _FakeClient();
      final playground = AiPlaygroundController(client: client)
        ..updateSettings(const PlaygroundSettings(systemPrompt: 'Be brief.'));
      playground.send('first');
      client.answer(<String>['one']);
      await pumpEventQueue();
      playground.send('second');
      expect(client.asked.last.map((m) => '${m.role}:${m.content}'), <String>[
        'system:Be brief.',
        'user:first',
        'assistant:one',
        'user:second',
      ]);
    },
  );

  test(
    'a send while an answer runs waits, and stop cancels the running one',
    () async {
      final client = _FakeClient();
      final playground = AiPlaygroundController(client: client);
      playground.send('a');
      playground.send('b');
      expect(client.asked, hasLength(1));
      playground.stop();
      expect(client.cancels, 1);
      client.answer(<String>[
        'x',
      ], const TextEvent(kind: 'done', finishReason: 'cancelled'));
      await pumpEventQueue();
      expect(playground.messages.last.figures!.finish, ChatFinish.cancelled);
    },
  );

  test('a failure shows its error and drops the empty answer', () async {
    final client = _FakeClient();
    final playground = AiPlaygroundController(client: client);
    playground.send('a');
    client.running!
      ..addError('the endpoint answered HTTP 404')
      ..close();
    await pumpEventQueue();
    expect(playground.error, contains('HTTP 404'));
    expect(playground.messages.map((m) => m.role), <ChatRole>[ChatRole.user]);
    expect(playground.busy, isFalse);
  });

  test('the bridge client hands the settings to the Rust core', () async {
    const client = DefaultTextClient();
    expect(client.localAvailable, isTrue);
    const settings = PlaygroundSettings(
      kind: PlaygroundSourceKind.local,
      modelDir: '/models/smollm2',
      provider: 'dml',
      maxNewTokens: 64,
    );
    await client.generate(settings, <TextMessage>[
      const TextMessage(role: 'user', content: 'hi'),
    ]).toList();
    expect(
      (rust.source!.modelDir, rust.source!.provider, rust.source!.baseUrl),
      ('/models/smollm2', 'dml', null),
    );
    expect(rust.options!.maxNewTokens, 64);
    expect(rust.messages!.single.content, 'hi');
    client.cancel();
    expect(rust.cancels, 1);
    final endpoint = const PlaygroundSettings(apiKey: '').source();
    expect(
      (endpoint.baseUrl, endpoint.model, endpoint.apiKey, endpoint.modelDir),
      ('http://127.0.0.1:18200', 'smollm2_135m_instruct-cpu', null, null),
    );
  });

  testWidgets('the view sends a typed message and shows the streamed answer', (
    tester,
  ) async {
    final client = _FakeClient();
    final playground = AiPlaygroundController(client: client);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: <LocalizationsDelegate<dynamic>>[
          ...AppLocalizations.localizationsDelegates,
          AnthologyLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: AiPlaygroundView(controller: playground),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField).last, 'Capital of France?');
    await tester.ensureVisible(find.byTooltip('Send'));
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    client.answer(<String>['Paris.']);
    await tester.pumpAndSettle();
    expect(find.textContaining('Paris.', findRichText: true), findsOneWidget);
    expect(find.textContaining('3 tokens'), findsOneWidget);
  });
}
