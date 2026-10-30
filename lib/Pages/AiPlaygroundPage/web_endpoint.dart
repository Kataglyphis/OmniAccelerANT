import 'dart:convert';
import 'dart:js_interop';

import 'package:omni_accelerant/Pages/AiPlaygroundPage/playground_settings.dart';
import 'package:omni_accelerant/src/rust/api/text.dart';
import 'package:web/web.dart' as web;

web.AbortController? _running;

/// One non-streamed chat completion, emitted as one `piece` and one `done` like the bridge's stream.
Stream<TextEvent> complete(
  PlaygroundSettings settings,
  List<TextMessage> messages,
) async* {
  final abort = web.AbortController();
  _running = abort;
  final body = jsonEncode(<String, Object>{
    'model': settings.model,
    'messages': [
      for (final m in messages) {'role': m.role, 'content': m.content},
    ],
    'max_tokens': settings.maxNewTokens,
    'temperature': settings.temperature,
  });
  final headers = <String, String>{
    'content-type': 'application/json',
    if (settings.apiKey.isNotEmpty)
      'authorization': 'Bearer ${settings.apiKey}',
  };
  final start = DateTime.now();
  final web.Response response;
  try {
    response = await web.window
        .fetch(
          '${settings.baseUrl}/v1/chat/completions'.toJS,
          web.RequestInit(
            method: 'POST',
            body: body.toJS,
            headers: headers.jsify() as web.HeadersInit,
            signal: abort.signal,
          ),
        )
        .toDart;
  } on Object {
    if (abort.signal.aborted) {
      yield const TextEvent(kind: 'done', finishReason: 'cancelled');
      return;
    }
    throw StateError('the endpoint at ${settings.baseUrl} is unreachable');
  }
  final text = (await response.text().toDart).toDart;
  if (!response.ok) {
    throw StateError('the endpoint answered HTTP ${response.status}: $text');
  }
  final answer = jsonDecode(text) as Map<String, dynamic>;
  final choice = (answer['choices'] as List).first as Map<String, dynamic>;
  final usage = answer['usage'] as Map<String, dynamic>? ?? const {};
  yield TextEvent(
    kind: 'piece',
    text: (choice['message'] as Map<String, dynamic>)['content'] as String,
  );
  yield TextEvent(
    kind: 'done',
    finishReason: choice['finish_reason'] as String? ?? 'stop',
    promptTokens: usage['prompt_tokens'] as int?,
    completionTokens: usage['completion_tokens'] as int?,
    timeToFirstTokenMs: DateTime.now()
        .difference(start)
        .inMilliseconds
        .toDouble(),
    decodeTokensPerSecond: 0,
  );
}

void cancel() => _running?.abort();
