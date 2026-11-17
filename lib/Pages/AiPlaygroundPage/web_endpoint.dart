import 'dart:async';
import 'dart:js_interop';

import 'package:omni_accelerant/Pages/AiPlaygroundPage/endpoint_chat.dart';
import 'package:omni_accelerant/Pages/AiPlaygroundPage/playground_settings.dart';
import 'package:omni_accelerant/src/rust/api/text.dart';
import 'package:omni_accelerant/utils/fetch_body_web.dart';
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
  return (status: response.status, body: fetchBodyChunks(response.body));
}
