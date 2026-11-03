import 'dart:convert';

import 'package:omni_accelerant/Pages/AiPlaygroundPage/playground_settings.dart';
import 'package:omni_accelerant/src/rust/api/text.dart';

/// The OpenAI chat-completions body the web build posts; seed, schema and stop appear only when set.
Map<String, Object?> chatCompletionBody(
  PlaygroundSettings settings,
  List<TextMessage> messages,
) => <String, Object?>{
  'model': settings.model,
  'messages': [
    for (final m in messages) {'role': m.role, 'content': m.content},
  ],
  'max_tokens': settings.maxNewTokens,
  'temperature': settings.temperature,
  if (settings.seed != null) 'seed': settings.seed,
  if (settings.jsonSchema.isNotEmpty)
    'response_format': <String, Object?>{
      'type': 'json_schema',
      'json_schema': <String, Object?>{
        'name': 'response',
        'schema': _schema(settings.jsonSchema),
        'strict': true,
      },
    },
  if (settings.stop.isNotEmpty) 'stop': settings.stop,
};

Object? _schema(String text) {
  final schema = jsonDecode(text);
  if (schema is! Map<String, Object?>) {
    throw FormatException('the JSON schema is not an object: $text');
  }
  return schema;
}
