// The hub's file is read from disk, which a browser run cannot; the VM lanes replay it.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_accelerant/Pages/AiPlaygroundPage/endpoint_reply.dart';

/// The hub's think split (ANTfrastructure CON288, owner D5): what a reply's pieces show and leave as answer.
const String _contract =
    'third_party/ANTfrastructure/shared/contracts/think-split.json';

/// What the splitter makes of [pieces], in the contract's display terms; final is the lab's, not this app's.
Map<String, Object?> _split(List<String> pieces) {
  final splitter = ThinkingSplitter();
  final shown = StringBuffer();
  var answer = '';
  for (final piece in pieces) {
    final late = splitter.lateCloses;
    final text = splitter.push(piece);
    // A late close turned the answer so far into thinking, as the playground's answer drops it.
    if (splitter.lateCloses > late) answer = '';
    shown.write(text);
    answer += text;
  }
  final rest = splitter.finish();
  shown.write(rest);
  answer += rest;
  return {
    'shown': shown.toString(),
    'answer': answer,
    'thinking': splitter.thinkingChars,
    'late_closes': splitter.lateCloses,
  };
}

void main() {
  final doc =
      jsonDecode(File(_contract).readAsStringSync()) as Map<String, dynamic>;
  final cases = (doc['cases'] as List).cast<Map<String, dynamic>>();

  test('the hub file still holds its cases', () {
    expect(cases.length, greaterThanOrEqualTo(11));
  });

  for (final item in cases) {
    test(item['name'] as String, () {
      final expected = Map<String, Object?>.of(
        item['expect'] as Map<String, dynamic>,
      )..remove('final');
      expect(_split((item['pieces'] as List).cast<String>()), expected);
    });
  }
}
