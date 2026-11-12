// The web build's chat client over the browser's fetch; what it reads from a reply is `endpoint_chat_test.dart`.
@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_accelerant/Pages/AiPlaygroundPage/playground_settings.dart';
import 'package:omni_accelerant/Pages/AiPlaygroundPage/web_endpoint.dart'
    as web_endpoint;
import 'package:omni_accelerant/src/rust/api/text.dart';
import 'package:web/web.dart' as web;

import 'support/fake_fetch.dart';

/// A 200 response whose body a test feeds chunk by chunk; aborting the request breaks it, as the browser's fetch does.
class _Body {
  _Body(web.AbortSignal? signal) {
    final source = JSObject()
      ..setProperty(
        'start'.toJS,
        ((web.ReadableStreamDefaultController feed) {
          _feed = feed;
        }).toJS,
      );
    response = web.Response(
      web.ReadableStream(source),
      web.ResponseInit(status: 200),
    );
    signal?.addEventListener(
      'abort',
      ((web.Event _) => _feed.error('aborted'.toJS)).toJS,
    );
  }

  late final web.ReadableStreamDefaultController _feed;
  late final web.Response response;

  void send(List<int> bytes) => _feed.enqueue(Uint8List.fromList(bytes).toJS);
}

const PlaygroundSettings _settings = PlaygroundSettings();
const List<TextMessage> _hi = <TextMessage>[
  TextMessage(role: 'user', content: 'How often?'),
];
const TextEvent _cancelled = TextEvent(kind: 'done', finishReason: 'cancelled');
const Duration _soon = Duration(seconds: 5);

Stream<TextEvent> _complete() => web_endpoint.complete(_settings, _hi);

/// A failure the page shows as exactly [words].
Matcher _saying(String words) =>
    emitsError(isA<Object>().having((f) => '$f', 'shown as', words));

/// Waits until [met], for a body that the browser hands over in its own time.
Future<void> _until(bool Function() met) async {
  for (var tries = 0; tries < 200 && !met(); tries++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(met(), isTrue);
}

void main() {
  test('the request is a JSON POST to the endpoint that can be aborted', () async {
    final requests = fakeFetch(
      (url) => respond(
        '{"choices":[{"message":{"content":"Twice."},"finish_reason":"stop"}],'
        '"usage":{"prompt_tokens":9,"completion_tokens":3}}',
      ),
    );
    final events = await web_endpoint
        .complete(_settings.copyWith(apiKey: 'k'), _hi)
        .toList();
    expect(events.first, const TextEvent(kind: 'piece', text: 'Twice.'));
    expect(
      (events.last.finishReason, events.last.completionTokens),
      ('stop', 3),
    );
    final web.RequestInit init = requests.single.init!;
    expect(requests.single.url, 'http://127.0.0.1:18200/v1/chat/completions');
    expect(init.method, 'POST');
    final JSString type = init.headers.getProperty('content-type'.toJS);
    final JSString key = init.headers.getProperty('authorization'.toJS);
    expect((type.toDart, key.toDart), ('application/json', 'Bearer k'));
    final body = jsonDecode((init.body! as JSString).toDart) as Map;
    expect(body['model'], _settings.model);
    expect(body['messages'], <Object>[
      <String, Object>{'role': 'user', 'content': 'How often?'},
    ]);
    expect(init.signal, isNotNull);
  });

  test(
    'an error inside a 200 answer is shown in the server\'s words',
    () async {
      fakeFetch((url) => respond('{"error":{"message":"model gone"}}'));
      await expectLater(_complete(), _saying('model gone'));
      fakeFetch((url) => respond('{"error":"model \'x\' not found"}'));
      await expectLater(_complete(), _saying("model 'x' not found"));
    },
  );

  test('an answer that was only thinking says so instead of failing on its null content', () async {
    fakeFetch(
      (url) => respond(
        '{"choices":[{"message":{"content":null,"reasoning_content":"Okay"},"finish_reason":"length"}],'
        '"usage":{"prompt_tokens":9,"completion_tokens":128}}',
      ),
    );
    await expectLater(
      _complete(),
      _saying(
        'the model gave no answer (finish_reason length): it spent its budget thinking '
        '(4 characters of thinking, 128 tokens); '
        'set a larger maximum of new tokens or switch thinking off at the endpoint',
      ),
    );
  });

  test('an answer without choices is a failure that shows it', () async {
    fakeFetch((url) => respond('{"choices":[]}'));
    await expectLater(
      _complete(),
      _saying("the endpoint's answer has no choices: {\"choices\":[]}"),
    );
  });

  test(
    'a status that is no success keeps the server\'s body as the reason',
    () async {
      fakeFetch((url) => respond('the model is loading', status: 503));
      await expectLater(
        _complete(),
        _saying('the endpoint answered HTTP 503: the model is loading'),
      );
    },
  );

  test('an answer without a body says that it is empty', () async {
    fakeFetch((url) => web.Response(null, web.ResponseInit(status: 204)));
    await expectLater(
      _complete(),
      _saying("the endpoint's answer is no chat reply: it is empty"),
    );
  });

  test('a request that fails says the endpoint is unreachable', () async {
    fakeFetch((url) => null);
    await expectLater(
      _complete(),
      _saying('the endpoint at http://127.0.0.1:18200 is unreachable'),
    );
  });

  test('Stop aborts a waiting request, which ends as cancelled', () async {
    final requests = fakeFetchWith((request) {
      final held = Completer<web.Response>();
      request.init!.signal!.addEventListener(
        'abort',
        ((web.Event _) => held.completeError(StateError('aborted'))).toJS,
      );
      return held.future;
    });
    final events = <TextEvent>[];
    final ended = _complete().forEach(events.add);
    await _until(() => requests.isNotEmpty);
    web_endpoint.cancel();
    await ended.timeout(_soon);
    expect(events, <TextEvent>[_cancelled]);
    expect(requests.single.init!.signal!.aborted, isTrue);
  });

  test(
    'a body is read as it arrives, and Stop inside it ends as cancelled',
    () async {
      late _Body body;
      fakeFetchWith(
        (request) async => (body = _Body(request.init?.signal)).response,
      );
      final events = <TextEvent>[];
      final ended = _complete().forEach(events.add);
      await pumpEventQueue();
      // The two chunks part inside the first é, which must arrive whole.
      final line = utf8.encode(
        'data: {"choices":[{"delta":{"content":"été"}}]}\n\n',
      );
      final cut = line.indexOf(0xC3) + 1;
      body
        ..send(line.sublist(0, cut))
        ..send(line.sublist(cut));
      await _until(() => events.isNotEmpty);
      expect(events, <TextEvent>[const TextEvent(kind: 'piece', text: 'été')]);
      web_endpoint.cancel();
      await ended.timeout(_soon);
      expect(events.last, _cancelled);
    },
  );

  test(
    'an error line fails at once though the server keeps the connection open',
    () async {
      late _Body body;
      fakeFetchWith(
        (request) async => (body = _Body(request.init?.signal)).response,
      );
      final failed = expectLater(_complete(), _saying('model gone'));
      await pumpEventQueue();
      body.send(utf8.encode('data: {"error":"model gone"}\n\n'));
      await failed.timeout(_soon);
    },
  );
}
