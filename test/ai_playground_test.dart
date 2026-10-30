// The AI Playground against a fake backend, and its bridge client against a mocked Rust core.
@TestOn('vm')
library;

import 'dart:async';

import 'package:anthology/Pages/Footer/default_footer_config.dart';
import 'package:anthology/Pages/Footer/footer.dart';
import 'package:anthology/Pages/Home/default_home_config.dart';
import 'package:anthology/Widgets/Chat/chat_entry.dart';
import 'package:anthology/app_attributes.dart';
import 'package:anthology/app_settings.dart';
import 'package:anthology/constants.dart';
import 'package:anthology/user_settings.dart';
import 'package:anthology/l10n/anthology_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_accelerant/Pages/AiPlaygroundPage/ai_playground_controller.dart';
import 'package:omni_accelerant/Pages/AiPlaygroundPage/ai_playground_page.dart';
import 'package:omni_accelerant/Pages/AiPlaygroundPage/playground_settings.dart';
import 'package:omni_accelerant/Pages/AiPlaygroundPage/text_client.dart';
import 'package:omni_accelerant/Pages/AiPlaygroundPage/web_endpoint_stub.dart'
    as web_endpoint_stub;
import 'package:omni_accelerant/Pages/omni_screen_configurations.dart';
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
  _FakeClient({this.local = false});

  final bool local;
  final List<List<TextMessage>> asked = <List<TextMessage>>[];
  StreamController<TextEvent>? running;
  int cancels = 0;

  @override
  bool get localAvailable => local;

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

Widget _localized(Widget child) => MaterialApp(
  localizationsDelegates: <LocalizationsDelegate<dynamic>>[
    ...AppLocalizations.localizationsDelegates,
    AnthologyLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

/// The page in the app's frame, footer off, as the device page's suite builds it.
Widget _page(AiPlaygroundController controller) {
  final userSettings = UserSettings(
    socialMediaLinksConfig: const {},
    businessEmail: 'test@example.com',
    myQuotation: '',
    firstName: 'Jane',
    lastName: 'Doe',
    aboutMeFileDe: 'about_de.md',
    aboutMeFileEn: 'about_en.md',
    assetPathImgOfMe: 'me.jpg',
  );
  final footerConfig = DefaultFooterConfig();
  final appAttributes = AppAttributes(
    footerConfig: footerConfig,
    homeConfig: DefaultHomeConfig(),
    appSettings: AppSettings(
      appNameDe: 'OmniAccelerANT',
      appNameEn: 'OmniAccelerANT',
      appTitleDe: 'OmniAccelerANT',
      appTitleEn: 'OmniAccelerANT',
      disableFooter: true,
    ),
    userSettings: userSettings,
    screenConfigurations: OmniScreenConfigurations(blogPageConfigs: const []),
    railAnimation: CurvedAnimation(
      parent: kAlwaysCompleteAnimation,
      curve: Curves.linear,
    ),
    showMediumSizeLayout: false,
    showLargeSizeLayout: false,
    colorSelected: ColorSeed.baseColor,
    useLightMode: true,
  );
  return _localized(
    AiPlaygroundPage(
      appAttributes: appAttributes,
      footer: Footer(
        footerPagesConfigs: const [],
        userSettings: userSettings,
        footerConfig: footerConfig,
      ),
      controller: controller,
    ),
  );
}

Future<void> _openSettings(
  WidgetTester tester,
  AiPlaygroundController controller,
) async {
  tester.view.physicalSize = const Size(1280, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    _localized(
      SingleChildScrollView(child: AiPlaygroundView(controller: controller)),
    ),
  );
  await tester.tap(find.text('Model and settings'));
  await tester.pumpAndSettle();
}

Finder _field(String label) => find.widgetWithText(TextFormField, label);

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

  test('settings copy every field and map onto the bridge', () {
    final settings = const PlaygroundSettings().copyWith(
      kind: PlaygroundSourceKind.local,
      modelDir: '/m',
      provider: 'cuda',
      baseUrl: 'http://lan:11434',
      model: 'qwen',
      apiKey: 'k',
      systemPrompt: 's',
      maxNewTokens: 9,
      temperature: 0.5,
    );
    expect(
      (
        settings.baseUrl,
        settings.model,
        settings.apiKey,
        settings.systemPrompt,
      ),
      ('http://lan:11434', 'qwen', 'k', 's'),
    );
    final source = settings.source();
    expect(
      (source.modelDir, source.provider, source.baseUrl),
      ('/m', 'cuda', null),
    );
    final endpoint = settings
        .copyWith(kind: PlaygroundSourceKind.endpoint)
        .source();
    expect(
      (endpoint.baseUrl, endpoint.model, endpoint.apiKey),
      ('http://lan:11434', 'qwen', 'k'),
    );
    final options = settings.options();
    expect(
      (options.maxNewTokens, options.temperature, options.topP, options.topK),
      (9, 0.5, 1.0, 50),
    );
  });

  test(
    'the fetch client is the web build\'s; native builds refuse it',
    () async {
      await expectLater(
        web_endpoint_stub.complete(
          const PlaygroundSettings(),
          const <TextMessage>[],
        ),
        emitsError(isA<UnsupportedError>()),
      );
      web_endpoint_stub.cancel();
    },
  );

  testWidgets('the endpoint fields set the next request', (tester) async {
    final playground = AiPlaygroundController(client: _FakeClient());
    await _openSettings(tester, playground);
    await tester.enterText(
      _field('Base URL (without /v1)'),
      ' http://lan:11434 ',
    );
    await tester.enterText(_field('Model'), 'qwen3:4b');
    await tester.enterText(_field('API key'), 'secret');
    await tester.enterText(_field('System prompt'), 'Answer in German.');
    await tester.enterText(_field('Maximum new tokens'), '64');
    await tester.enterText(_field('Maximum new tokens'), 'many');
    await tester.drag(find.byType(Slider), const Offset(200, 0));
    await tester.pump();
    final s = playground.settings;
    expect(
      (s.baseUrl, s.model, s.apiKey, s.systemPrompt, s.maxNewTokens),
      ('http://lan:11434', 'qwen3:4b', 'secret', 'Answer in German.', 64),
    );
    expect(s.temperature, greaterThan(0));
    expect(
      find.textContaining('This build runs no local model'),
      findsOneWidget,
    );
  });

  testWidgets(
    'where GenAI loads, the local source takes a directory and a provider',
    (tester) async {
      final playground = AiPlaygroundController(
        client: _FakeClient(local: true),
      );
      await _openSettings(tester, playground);
      expect(
        find.textContaining('This build runs no local model'),
        findsNothing,
      );
      await tester.tap(find.text('Local model'));
      await tester.pumpAndSettle();
      await tester.enterText(
        _field('GenAI model directory'),
        '/models/smollm2',
      );
      await tester.tap(find.text('CPU'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CUDA').last);
      await tester.pumpAndSettle();
      final s = playground.settings;
      expect(
        (s.kind, s.modelDir, s.provider),
        (PlaygroundSourceKind.local, '/models/smollm2', 'cuda'),
      );
    },
  );

  testWidgets(
    'the page shows a failure above the chat and clears the conversation',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final client = _FakeClient();
      final playground = AiPlaygroundController(client: client);
      await tester.pumpWidget(_page(playground));
      expect(find.text('AI Playground'), findsOneWidget);
      playground.send('hi');
      client.running!
        ..addError('the endpoint is unreachable')
        ..close();
      await tester.pumpAndSettle();
      expect(
        find.textContaining('The model failed: the endpoint is unreachable'),
        findsOneWidget,
      );
      await tester.tap(find.text('New conversation'));
      await tester.pumpAndSettle();
      expect(playground.messages, isEmpty);
      expect(find.textContaining('The model failed'), findsNothing);
    },
  );
}
