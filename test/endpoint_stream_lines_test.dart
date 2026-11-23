// The hub's files are read from disk, which a browser run cannot; the VM lanes replay them.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_accelerant/Pages/AiPlaygroundPage/endpoint_reply.dart';

/// The hub's OpenAI contracts (ANTfrastructure CON237, CON288), the files OxidANT and OrchestrANT replay too.
const String _contracts = 'third_party/ANTfrastructure/shared/contracts';

List<Map<String, dynamic>> _cases(String file) {
  final doc = jsonDecode(File('$_contracts/$file').readAsStringSync());
  return ((doc as Map<String, dynamic>)['cases'] as List)
      .cast<Map<String, dynamic>>();
}

/// What the reader makes of [lines], in the contract's terms; it stops at `[DONE]`, as the playground does.
Map<String, Object?> _read(List<String> lines) {
  final text = StringBuffer();
  final thinking = StringBuffer();
  String? finish;
  List<int>? usage;
  var done = false;
  try {
    for (final line in lines) {
      final part = parseStreamLine(line);
      if (part == null) continue;
      text.write(part.text);
      thinking.write(part.thinking);
      finish = part.finish ?? finish;
      if (part.usage case final u?) usage = [u.prompt, u.completion];
      if (part.done) {
        done = true;
        break;
      }
    }
  } on EndpointFailure catch (failure) {
    return {'error': failure.reason};
  }
  return {
    'text': text.toString(),
    'thinking': thinking.toString(),
    'finish': finish,
    'usage': usage,
    'done': done,
  };
}

/// What the reader makes of a whole answer's [body], in the contract's terms.
Map<String, Object?> _whole(String body) {
  try {
    final part = parseWholeAnswer(body);
    final usage = part.usage;
    return {
      'text': part.text,
      'thinking': part.thinking,
      'finish': part.finish,
      'usage': usage == null ? null : [usage.prompt, usage.completion],
    };
  } on EndpointFailure catch (failure) {
    return {'error': failure.reason};
  }
}

/// An expected error matches as a substring, as in every binding.
void _check(Map<String, Object?> got, Map<String, dynamic> expected) {
  if (expected.containsKey('error')) {
    expect(got.keys, ['error']);
    expect(got['error'] as String, contains(expected['error'] as String));
  } else {
    expect(got, expected);
  }
}

void main() {
  final lines = _cases('openai-stream-lines.json');
  final answers = _cases('openai-chat-answers.json');

  test('the hub files still hold their cases', () {
    expect(lines.length, greaterThanOrEqualTo(22));
    expect(answers.length, greaterThanOrEqualTo(10));
  });

  for (final item in lines) {
    test(item['name'] as String, () {
      _check(
        _read((item['lines'] as List).cast<String>()),
        item['expect'] as Map<String, dynamic>,
      );
    });
  }

  group('whole answers', () {
    for (final item in answers) {
      test(item['name'] as String, () {
        _check(
          _whole(item['body'] as String),
          item['expect'] as Map<String, dynamic>,
        );
      });
    }
  });
}
