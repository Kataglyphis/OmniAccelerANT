import 'package:omni_accelerant/Pages/AiPlaygroundPage/playground_settings.dart';
import 'package:omni_accelerant/src/rust/api/text.dart';

/// Native builds stream through OxidANT's bridge and never call these.
Stream<TextEvent> complete(
  PlaygroundSettings settings,
  List<TextMessage> messages,
) => Stream<TextEvent>.error(
  UnsupportedError('the fetch endpoint client is the web build\'s'),
);

void cancel() {}
