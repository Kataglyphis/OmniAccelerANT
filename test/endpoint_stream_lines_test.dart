// The hub's file is read from disk, which a browser run cannot; the VM lanes replay it.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_accelerant/Pages/AiPlaygroundPage/endpoint_reply.dart';

/// The hub's OpenAI stream lines (ANTfrastructure CON237), the file OxidANT and OrchestrANT replay too.
const String _contract =
    'third_party/ANTfrastructure/shared/contracts/openai-stream-lines.json';

/// What the reader makes of [lines], in the contract's terms.
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
      done = done || part.done;
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

void main() {
  final contract =
      jsonDecode(File(_contract).readAsStringSync()) as Map<String, dynamic>;
  final cases = (contract['cases'] as List).cast<Map<String, dynamic>>();

  test('the hub file still holds its cases', () {
    expect(cases.length, greaterThanOrEqualTo(11));
  });

  for (final item in cases) {
    test(item['name'] as String, () {
      final got = _read((item['lines'] as List).cast<String>());
      final expected = item['expect'] as Map<String, dynamic>;
      if (expected.containsKey('error')) {
        expect(got.keys, ['error']);
        expect(got['error'] as String, contains(expected['error'] as String));
      } else {
        expect(got, expected);
      }
    });
  }
}
