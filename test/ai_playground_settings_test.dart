// The playground's saved settings and request body: what survives a restart, and that the API key never does.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:anthology/l10n/anthology_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_accelerant/Pages/AiPlaygroundPage/ai_playground_controller.dart';
import 'package:omni_accelerant/Pages/AiPlaygroundPage/ai_playground_page.dart';
import 'package:omni_accelerant/Pages/AiPlaygroundPage/endpoint_request.dart';
import 'package:omni_accelerant/Pages/AiPlaygroundPage/playground_settings.dart';
import 'package:omni_accelerant/Pages/AiPlaygroundPage/playground_settings_store.dart';
import 'package:omni_accelerant/Pages/AiPlaygroundPage/playground_settings_store_io.dart';
import 'package:omni_accelerant/Pages/AiPlaygroundPage/text_client.dart';
import 'package:omni_accelerant/l10n/app_localizations.dart';
import 'package:omni_accelerant/src/rust/api/text.dart';

const String _planted = 'planted-never-on-disk';

const PlaygroundSettings _custom = PlaygroundSettings(
  kind: PlaygroundSourceKind.local,
  modelDir: '/models/smollm2',
  provider: 'cuda',
  baseUrl: 'http://lan:11434',
  model: 'qwen3:4b',
  apiKey: _planted,
  systemPrompt: 'Answer in German.',
  maxNewTokens: 64,
  temperature: 0.7,
  seed: 42,
  jsonSchema: '{"type":"object"}',
  stop: <String>['\n\n', 'END'],
);

class _NoClient implements TextClient {
  @override
  bool get localAvailable => true;

  @override
  Stream<TextEvent> generate(
    PlaygroundSettings settings,
    List<TextMessage> messages,
  ) => const Stream<TextEvent>.empty();

  @override
  void cancel() {}
}

/// Every byte under [root], so a key written to any file, partial or not, is found.
String _everyByte(Directory root) => <String>[
  for (final entity in root.listSync(recursive: true))
    if (entity is File) latin1.decode(entity.readAsBytesSync()),
].join('\n');

void _expectSameButKey(PlaygroundSettings a, PlaygroundSettings b) {
  expect(jsonEncode(a.toJson()), jsonEncode(b.toJson()));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('playground-'));
  tearDown(() => dir.deleteSync(recursive: true));

  FilePlaygroundSettingsStore store() =>
      FilePlaygroundSettingsStore(() async => dir);

  test(
    'settings survive a restart, and the planted API key is never written',
    () async {
      final first = AiPlaygroundController(client: _NoClient(), store: store())
        ..updateSettings(const PlaygroundSettings(apiKey: _planted))
        ..updateSettings(_custom);
      await first.saved;
      expect(first.error, isNull);
      expect(File('${dir.path}/$settingsFileName').existsSync(), isTrue);
      expect(_everyByte(dir), isNot(contains(_planted)));
      expect(_everyByte(dir), isNot(contains('planted-never')));

      final restarted = AiPlaygroundController(
        client: _NoClient(),
        store: store(),
      );
      await restarted.restore();
      expect(restarted.error, isNull);
      expect(restarted.restored, 1);
      _expectSameButKey(restarted.settings, _custom);
      expect(restarted.settings.apiKey, isEmpty);
      expect(restarted.settings.seed, 42);
      expect(restarted.settings.stop, <String>['\n\n', 'END']);
    },
  );

  test('a key typed before the restore stays in memory only', () async {
    await store().save(_custom.copyWith(apiKey: ''));
    final playground = AiPlaygroundController(
      client: _NoClient(),
      store: store(),
    )..settings = const PlaygroundSettings(apiKey: 'typed');
    await playground.restore();
    expect(playground.settings.apiKey, 'typed');
    expect(playground.settings.model, 'qwen3:4b');
  });

  test('nothing saved yet keeps the defaults', () async {
    final playground = AiPlaygroundController(
      client: _NoClient(),
      store: store(),
    );
    await playground.restore();
    expect((playground.restored, playground.error), (0, null));
    _expectSameButKey(playground.settings, const PlaygroundSettings());
  });

  test('a broken file shows its error and keeps the defaults', () async {
    File('${dir.path}/$settingsFileName').writeAsStringSync('[1, 2]');
    final playground = AiPlaygroundController(
      client: _NoClient(),
      store: store(),
    );
    await playground.restore();
    expect(playground.error, contains('not an object'));
    _expectSameButKey(playground.settings, const PlaygroundSettings());
  });

  test('a store that cannot write shows its error', () async {
    final failing = FilePlaygroundSettingsStore(
      () async => throw const FileSystemException('read-only'),
    );
    final playground = AiPlaygroundController(
      client: _NoClient(),
      store: failing,
    )..updateSettings(_custom);
    await playground.saved;
    expect(playground.error, contains('could not be saved'));
  });

  test('a mistyped or unknown field is refused', () {
    expect(
      () => PlaygroundSettings.fromJson(<String, Object?>{'kind': 'cloud'}),
      throwsFormatException,
    );
    expect(
      () => PlaygroundSettings.fromJson(<String, Object?>{'seed': 'x'}),
      throwsFormatException,
    );
    expect(
      () => PlaygroundSettings.fromJson(<String, Object?>{
        'stop': <Object?>[1],
      }),
      throwsFormatException,
    );
    expect(
      PlaygroundSettings.fromJson(<String, Object?>{'temperature': 1})
          .temperature,
      1.0,
    );
  });

  test('the default store writes to the support directory', () async {
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => dir.path);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final saved = defaultPlaygroundSettingsStore();
    await saved.save(_custom);
    _expectSameButKey((await saved.load())!, _custom);
    expect(_everyByte(dir), isNot(contains(_planted)));
  });

  test('the request body carries seed, schema and stop only when set', () {
    const messages = <TextMessage>[TextMessage(role: 'user', content: 'hi')];
    final plain = chatCompletionBody(const PlaygroundSettings(), messages);
    expect(plain.keys, <String>[
      'model',
      'messages',
      'max_tokens',
      'temperature',
    ]);
    final body = chatCompletionBody(_custom, messages);
    expect(body['seed'], 42);
    expect(body['stop'], <String>['\n\n', 'END']);
    expect(body['response_format'], <String, Object?>{
      'type': 'json_schema',
      'json_schema': <String, Object?>{
        'name': 'response',
        'schema': <String, Object?>{'type': 'object'},
        'strict': true,
      },
    });
    expect(jsonEncode(body), isNot(contains(_planted)));
    expect(
      () => chatCompletionBody(
        const PlaygroundSettings(jsonSchema: '[]'),
        messages,
      ),
      throwsFormatException,
    );
  });

  testWidgets('the seed, schema and stop fields set the next request', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final playground = AiPlaygroundController(client: _NoClient());
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
    await tester.tap(find.text('Model and settings'));
    await tester.pumpAndSettle();
    Finder field(String label) => find.widgetWithText(TextFormField, label);
    await tester.enterText(
      field('Seed (empty: a fresh answer each time)'),
      '7',
    );
    await tester.enterText(
      field('JSON schema for the answer (empty: free text)'),
      ' {"type":"object"} ',
    );
    await tester.enterText(field('Stop strings, one per line'), 'END\n\nSTOP');
    await tester.pump();
    expect(
      (playground.settings.seed, playground.settings.jsonSchema),
      (7, '{"type":"object"}'),
    );
    expect(playground.settings.stop, <String>['END', 'STOP']);
    await tester.enterText(
      field('Seed (empty: a fresh answer each time)'),
      'x',
    );
    expect(playground.settings.seed, 7);
    await tester.enterText(
      field('Seed (empty: a fresh answer each time)'),
      '2147483648',
    );
    expect(playground.settings.seed, 7);
    await tester.enterText(
      field('Seed (empty: a fresh answer each time)'),
      ' ',
    );
    expect(playground.settings.seed, isNull);
  });
}
