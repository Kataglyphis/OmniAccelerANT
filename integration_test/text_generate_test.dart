import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:omni_accelerant/Pages/AiPlaygroundPage/ai_playground_controller.dart';
import 'package:omni_accelerant/Pages/AiPlaygroundPage/playground_settings.dart';
import 'package:omni_accelerant/src/rust/api/text.dart';
import 'package:omni_accelerant/src/rust/frb_generated.dart';

/// The lane writes both: the hub's tiny GenAI model and the SmolLM2-135M directory from OxidANT's llm.lock.
const String _tinyModel = String.fromEnvironment('KATAGLYPHIS_TINY_MODEL_DIR');
const String _smolModel = String.fromEnvironment('KATAGLYPHIS_LLM_MODEL_DIR');

Future<(String, TextEvent)> _answer(
  String modelDir,
  String prompt,
  int maxNewTokens,
) async {
  final events = await textGenerate(
    source: TextSource(modelDir: modelDir, provider: 'cpu'),
    messages: <TextMessage>[TextMessage(role: 'user', content: prompt)],
    options: TextOptions(
      maxNewTokens: maxNewTokens,
      temperature: 0,
      topP: 1,
      topK: 50,
      stop: const <String>[],
    ),
  ).toList();
  final text = events.where((e) => e.kind == 'piece').map((e) => e.text).join();
  return (text, events.last);
}

/// The chain GenAI in the app process, through OxidANT's bridge, with the models the lane fetched.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await RustLib.init();
  });

  test('the bridge loads the chain GenAI', () {
    expect(
      _tinyModel,
      isNotEmpty,
      reason: 'the lane passes it as --dart-define',
    );
    expect(
      _smolModel,
      isNotEmpty,
      reason: 'the lane passes it as --dart-define',
    );
    expect(textLocalAvailable(), isTrue);
  });

  test('greedy decoding of the tiny model yields exactly defg', () async {
    final (text, done) = await _answer(_tinyModel, 'abc', 4);
    debugPrint('tiny model answer: $text');
    expect(text, 'defg');
    expect(
      (done.kind, done.finishReason, done.completionTokens),
      ('done', 'length', 4),
    );
  });

  test('SmolLM2-135M names Paris as the capital of France', () async {
    final (text, done) = await _answer(
      _smolModel,
      'What is the capital of France?',
      32,
    );
    debugPrint('SmolLM2-135M answer: $text');
    expect(text, contains('Paris'));
    expect(done.finishReason, isNotNull);
  });

  test(
    'the playground sends seed, response_format and stop to the endpoint',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final bodies = <Map<String, Object?>>[];
      server.listen((request) async {
        bodies.add(
          jsonDecode(await utf8.decodeStream(request)) as Map<String, Object?>,
        );
        request.response.headers.contentType = ContentType(
          'text/event-stream',
          '',
        );
        request.response.write(
          'data: {"choices":[{"delta":{"content":"{}"},"finish_reason":null}]}\n\n'
          'data: {"choices":[{"delta":{},"finish_reason":"stop"}],'
          '"usage":{"prompt_tokens":3,"completion_tokens":1}}\n\n'
          'data: [DONE]\n\n',
        );
        await request.response.close();
      });
      addTearDown(server.close);
      final playground = AiPlaygroundController()
        ..updateSettings(
          PlaygroundSettings(
            baseUrl: 'http://127.0.0.1:${server.port}',
            model: 'tiny',
            temperature: 1,
            seed: 7,
            jsonSchema: '{"type":"object"}',
            stop: const <String>['END'],
          ),
        );
      playground.send('hi');
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (playground.busy && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(playground.error, isNull);
      expect(playground.messages.last.text, '{}');
      final body = bodies.single;
      debugPrint('recorded request body: ${jsonEncode(body)}');
      expect(body['seed'], 7);
      expect(body['stop'], <String>['END']);
      final format = body['response_format']! as Map<String, Object?>;
      expect(format['type'], 'json_schema');
      expect(
        (format['json_schema']! as Map<String, Object?>)['schema'],
        <String, Object?>{'type': 'object'},
      );
    },
  );
}
