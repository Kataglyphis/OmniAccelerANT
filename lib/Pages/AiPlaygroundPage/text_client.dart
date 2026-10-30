import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:omni_accelerant/Pages/AiPlaygroundPage/playground_settings.dart';
import 'package:omni_accelerant/Pages/AiPlaygroundPage/web_endpoint_stub.dart'
    if (dart.library.js_interop) 'package:omni_accelerant/Pages/AiPlaygroundPage/web_endpoint.dart'
    as web_endpoint;
import 'package:omni_accelerant/src/rust/api/text.dart';

/// What the playground needs from a language-model backend; widget tests hand it a fake.
abstract class TextClient {
  /// Whether this build runs a model directory in process.
  bool get localAvailable;

  /// Streams `piece` events, then one `done`; a failure arrives as a stream error.
  Stream<TextEvent> generate(
    PlaygroundSettings settings,
    List<TextMessage> messages,
  );

  void cancel();
}

/// OxidANT's text bridge on native builds; on the web, whose build has no such bridge, one whole answer over fetch.
class DefaultTextClient implements TextClient {
  const DefaultTextClient();

  @override
  bool get localAvailable => !kIsWeb && textLocalAvailable();

  @override
  Stream<TextEvent> generate(
    PlaygroundSettings settings,
    List<TextMessage> messages,
  ) => kIsWeb
      ? web_endpoint.complete(settings, messages)
      : textGenerate(
          source: settings.source(),
          messages: messages,
          options: settings.options(),
        );

  @override
  void cancel() => kIsWeb ? web_endpoint.cancel() : textCancel();
}
