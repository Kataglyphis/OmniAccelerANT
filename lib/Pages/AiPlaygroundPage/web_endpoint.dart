import 'dart:async';
import 'dart:js_interop';

import 'package:omni_accelerant/Pages/AiPlaygroundPage/endpoint_chat.dart';
import 'package:omni_accelerant/Pages/AiPlaygroundPage/playground_settings.dart';
import 'package:omni_accelerant/src/rust/api/text.dart';
import 'package:web/web.dart' as web;

final EndpointChat _chat = EndpointChat(_fetch);

/// One chat completion over the browser's fetch, as `piece` and `done` events like the bridge's stream.
Stream<TextEvent> complete(
  PlaygroundSettings settings,
  List<TextMessage> messages,
) => _chat.complete(settings, messages);

void cancel() => _chat.cancel();

/// The browser's fetch as the chat client's transport; [cancel] aborts the request and its body.
Future<EndpointReply> _fetch(
  String url,
  Map<String, String> headers,
  String body, {
  required Future<void> cancel,
}) async {
  final abort = web.AbortController();
  unawaited(cancel.then((_) => abort.abort()));
  final response = await web.window
      .fetch(
        url.toJS,
        web.RequestInit(
          method: 'POST',
          body: body.toJS,
          headers: headers.jsify() as web.HeadersInit,
          signal: abort.signal,
        ),
      )
      .toDart;
  return (status: response.status, body: _chunks(response.body));
}

/// The bytes of [body] as they arrive; a listener that leaves ends the read at once, also during a silence.
Stream<List<int>> _chunks(web.ReadableStream? body) {
  if (body == null) return const Stream<List<int>>.empty();
  final reader = body.getReader() as web.ReadableStreamDefaultReader;
  final chunks = StreamController<List<int>>();
  chunks.onListen = () => unawaited(_pump(reader, chunks));
  // An aborted body refuses the cancel, which then has nothing left to end.
  chunks.onCancel = () => reader.cancel().toDart.ignore();
  return chunks.stream;
}

Future<void> _pump(
  web.ReadableStreamDefaultReader reader,
  StreamController<List<int>> chunks,
) async {
  try {
    while (true) {
      final read = await reader.read().toDart;
      if (read.done) break;
      chunks.add((read.value! as JSUint8Array).toDart);
    }
  } on Object catch (failure) {
    chunks.addError(failure);
  }
  await chunks.close();
}
