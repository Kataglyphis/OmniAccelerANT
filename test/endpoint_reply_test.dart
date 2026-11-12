// What the web build's chat client reads from an endpoint's reply; the client itself is `endpoint_chat_test.dart`.
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_accelerant/Pages/AiPlaygroundPage/endpoint_reply.dart';

ReplyPart _part({
  String thinking = '',
  String text = '',
  String? finish,
  ({int prompt, int completion})? usage,
  bool done = false,
}) =>
    (thinking: thinking, text: text, finish: finish, usage: usage, done: done);

Matcher _failsWith(Object reason) =>
    throwsA(isA<EndpointFailure>().having((f) => f.reason, 'reason', reason));

/// Runs [pieces] through a splitter: the answer each piece settled with `|` between, the rest at the end, the thinking count.
(String, String, int) _split(List<String> pieces) {
  final splitter = ThinkingSplitter();
  final shown = <String>[for (final piece in pieces) splitter.push(piece)]
      .where((text) => text.isNotEmpty)
      .join('|');
  return (shown, splitter.finish(), splitter.thinkingChars);
}

/// The answer [pieces] leave and their thinking count; a late close empties the answer, as the client reads it.
(String, int) _answer(List<String> pieces) {
  final splitter = ThinkingSplitter();
  var answer = '';
  for (final piece in pieces) {
    final late = splitter.lateCloses;
    final text = splitter.push(piece);
    answer = splitter.lateCloses > late ? text : answer + text;
  }
  return (answer + splitter.finish(), splitter.thinkingChars);
}

void main() {
  group('parseStreamLine', () {
    test(
      'a data line gives its text with or without a space after the colon',
      () {
        const chunk = '{"choices":[{"index":0,"delta":{"content":"Hi"}}]}';
        expect(parseStreamLine('data: $chunk'), _part(text: 'Hi'));
        expect(parseStreamLine('data:$chunk'), _part(text: 'Hi'));
        expect(parseStreamLine('data:   $chunk  '), _part(text: 'Hi'));
      },
    );

    test('a line that is no data line carries nothing', () {
      for (final line in <String>['', ': keep-alive', 'event: message', '{']) {
        expect(parseStreamLine(line), isNull, reason: line);
      }
    });

    test(
      'the [DONE] line says that nothing follows and is not read as JSON',
      () {
        expect(parseStreamLine('data: [DONE]'), _part(done: true));
        expect(parseStreamLine('data:[DONE]'), _part(done: true));
      },
    );

    test('a usage chunk without choices carries the two counts', () {
      expect(
        parseStreamLine(
          'data: {"choices":[],"usage":{"prompt_tokens":9,"completion_tokens":3,"total_tokens":12}}',
        ),
        _part(usage: (prompt: 9, completion: 3)),
      );
      // A count the server left out reads as 0, as the native client reads it.
      expect(
        parseStreamLine('data: {"usage":{"completion_tokens":3}}'),
        _part(usage: (prompt: 0, completion: 3)),
      );
    });

    test('a finish reason is length, or stop for every other word', () {
      String? finish(String reason) => parseStreamLine(
        'data: {"choices":[{"delta":{},"finish_reason":$reason}]}',
      )?.finish;
      expect(finish('"length"'), 'length');
      expect(finish('"stop"'), 'stop');
      expect(finish('"tool_calls"'), 'stop');
      expect(finish('null'), isNull);
    });

    test('reasoning_content and reasoning are thinking, never answer text', () {
      // llama-server and vLLM.
      expect(
        parseStreamLine(
          'data: {"choices":[{"finish_reason":null,"index":0,"delta":{"reasoning_content":"Okay"}}]}',
        ),
        _part(thinking: 'Okay'),
      );
      // Ollama.
      expect(
        parseStreamLine(
          'data: {"choices":[{"index":0,"delta":{"role":"assistant","content":"","reasoning":"Okay"},"finish_reason":null}]}',
        ),
        _part(thinking: 'Okay'),
      );
      expect(
        parseStreamLine(
          'data: {"choices":[{"delta":{"reasoning_content":"so","content":"Yes"}}]}',
        ),
        _part(thinking: 'so', text: 'Yes'),
      );
      // A server that sends both names means one thought, not two.
      expect(
        parseStreamLine(
          'data: {"choices":[{"delta":{"reasoning":"Okay","reasoning_content":"Okay"}}]}',
        ),
        _part(thinking: 'Okay'),
      );
      expect(
        parseStreamLine(
          'data: {"choices":[{"delta":{"reasoning_content":"","reasoning":null,"content":null}}]}',
        ),
        _part(),
      );
    });

    test('an error object ends the reply with the server\'s words', () {
      expect(
        () => parseStreamLine(
          'data: {"error":{"message":"model gone","type":"server_error"}}',
        ),
        _failsWith('model gone'),
      );
    });

    test(
      'an error sent as plain text ends the reply with the server\'s words',
      () {
        expect(
          () => parseStreamLine('data: {"error":"model \'x\' not found"}'),
          _failsWith("model 'x' not found"),
        );
      },
    );

    test('a field of a wrong type carries nothing and is no type error', () {
      for (final chunk in <String>[
        '{"choices":[7],"usage":[3]}',
        '{"choices":{"delta":{"content":"Hi"}},"usage":"none"}',
        '{"choices":[{"delta":"Hi","finish_reason":5}]}',
        '{"choices":[{"delta":{"content":["Hi"],"reasoning":7}}],"error":null}',
      ]) {
        expect(parseStreamLine('data: $chunk'), _part(), reason: chunk);
      }
      expect(
        parseStreamLine(
          'data: {"usage":{"prompt_tokens":"9","completion_tokens":3.0}}',
        ),
        _part(usage: (prompt: 0, completion: 3)),
      );
    });

    test('a data line without data is a failure that says so', () {
      expect(
        () => parseStreamLine('data:'),
        _failsWith('an unreadable stream chunk: it is empty'),
      );
    });

    test('an error without a message is shown as it came', () {
      expect(
        () => parseStreamLine('data: {"error":{"code":503}}'),
        _failsWith('{"code":503}'),
      );
    });

    test('a chunk that is not a JSON object is a failure that shows it', () {
      expect(
        () => parseStreamLine('data: {"choices":[{"delta"'),
        _failsWith('an unreadable stream chunk: {"choices":[{"delta"'),
      );
      expect(
        () => parseStreamLine('data: 42'),
        _failsWith('an unreadable stream chunk: 42'),
      );
    });
  });

  group('parseWholeAnswer', () {
    test(
      'a whole answer gives its text, thinking, finish reason and usage',
      () {
        expect(
          parseWholeAnswer(
            '{"choices":[{"index":0,"message":{"role":"assistant","content":"Twice.","reasoning_content":"hm"},'
            '"finish_reason":"length"}],"usage":{"prompt_tokens":9,"completion_tokens":3}}',
          ),
          _part(
            thinking: 'hm',
            text: 'Twice.',
            finish: 'length',
            usage: (prompt: 9, completion: 3),
            done: true,
          ),
        );
      },
    );

    test('a whole answer without a finish reason ended on its own', () {
      expect(
        parseWholeAnswer('{"choices":[{"message":{"content":"Yes"}}]}'),
        _part(text: 'Yes', finish: 'stop', done: true),
      );
    });

    test('a content that is no text reads as no text, not as a type error', () {
      for (final content in <String>['null', '7', '[]']) {
        expect(
          parseWholeAnswer(
            '{"choices":[{"message":{"content":$content},"finish_reason":"stop"}]}',
          ),
          _part(finish: 'stop', done: true),
          reason: content,
        );
      }
      expect(
        parseWholeAnswer('{"choices":[{"finish_reason":"stop"}]}'),
        _part(finish: 'stop', done: true),
      );
    });

    test('a whole answer without choices is a failure that shows it', () {
      for (final body in <String>[
        '{"choices":[]}',
        '{"id":"x"}',
        '{"choices":[7]}',
        '{"choices":"none"}',
      ]) {
        expect(
          () => parseWholeAnswer(body),
          _failsWith("the endpoint's answer has no choices: $body"),
        );
      }
    });

    test(
      'a whole answer that carries an error fails with the server\'s words',
      () {
        expect(
          () => parseWholeAnswer('{"error":{"message":"model gone"}}'),
          _failsWith('model gone'),
        );
        expect(
          () => parseWholeAnswer('{"error":"model \'x\' not found"}'),
          _failsWith("model 'x' not found"),
        );
      },
    );

    test('a body that is no JSON object is a failure that shows its start', () {
      expect(
        () => parseWholeAnswer('<html>not found</html>\n'),
        _failsWith(
          "the endpoint's answer is no chat reply: <html>not found</html>",
        ),
      );
      expect(
        () => parseWholeAnswer('x' * 5000),
        _failsWith(endsWith(': ${'x' * 2000}')),
      );
      expect(
        () => parseWholeAnswer(' \n'),
        _failsWith("the endpoint's answer is no chat reply: it is empty"),
      );
    });
  });

  group('ReplyReader', () {
    test(
      'data lines are read as they come and nothing is left for the end',
      () {
        final reader = ReplyReader();
        expect(reader.line(': keep-alive'), isNull);
        expect(
          reader.line('data: {"choices":[{"delta":{"content":"Hi"}}]}'),
          _part(text: 'Hi'),
        );
        expect(reader.line(''), isNull);
        expect(reader.line('data: [DONE]'), _part(done: true));
        expect(reader.streamed, isTrue);
        expect(reader.end(), isNull);
      },
    );

    test(
      'a body without data lines is one whole answer, also over many lines',
      () {
        final reader = ReplyReader();
        for (final line in <String>[
          '{',
          '  "choices": [{"message": {"content": "Yes"}, "finish_reason": "stop"}]',
          '}',
        ]) {
          expect(reader.line(line), isNull);
        }
        expect(reader.streamed, isFalse);
        expect(reader.end(), _part(text: 'Yes', finish: 'stop', done: true));
      },
    );
  });

  group('ThinkingSplitter', () {
    test('a think block is counted and left out of the answer', () {
      expect(_split(<String>['<think>', 'hm, cats', '</think>', 'Twice.']), (
        'Twice.',
        '',
        '<think>hm, cats</think>'.length,
      ));
      // One piece may hold the whole block, text before it and text after it.
      expect(_split(<String>['A <think>x</think>B']), (
        'A B',
        '',
        '<think>x</think>'.length,
      ));
    });

    test('a tag split over two pieces is held back until it is decided', () {
      expect(_split(<String>['Hi <th', 'ink>secret</thi', 'nk> there']), (
        'Hi |there',
        '',
        '<think>secret</think>'.length,
      ));
    });

    test('a closing tag alone makes everything before it thinking', () {
      // The chat template opened the block in the prompt, so the reply holds only its end.
      const pieces = <String>[
        'Okay, the user',
        ' asks.\n',
        '</think>',
        '\n\n',
        'Twice.',
      ];
      const thinking = 'Okay, the user asks.\n</think>';
      // What was given out before the tag came cannot be taken back.
      expect(_split(pieces), (
        'Okay, the user| asks.\n|Twice.',
        '',
        thinking.length,
      ));
      expect(_answer(pieces), ('Twice.', thinking.length));
      // In one piece nothing was given out yet, so the thinking is never seen.
      expect(_split(<String>['hm</think>\n\nTwice.']), ('Twice.', '', 10));
      final splitter = ThinkingSplitter()..push('hm</think>');
      expect(splitter.lateCloses, 1);
      // A block that was opened is no late close.
      expect((ThinkingSplitter()..push('<think>x</think>')).lateCloses, 0);
    });

    test('white space after a closing tag is dropped, also piece by piece', () {
      // The dropped white space is neither answer nor thinking.
      expect(
        _split(<String>[
          '<think>x</think>',
          '\n',
          '\n ',
          'Twice.\n',
          ' Or so.',
        ]),
        ('Twice.\n| Or so.', '', '<think>x</think>'.length),
      );
      expect(_split(<String>['<think>x</think>\n\n']), ('', '', 16));
      // White space anywhere else is the model's own.
      expect(_split(<String>['\n A\n\nB ']), ('\n A\n\nB ', '', 0));
    });

    test('text that only begins like a tag is answer once it is decided', () {
      expect(_split(<String>['a <', 'b and <thin', ' air', ' <']), (
        'a |<b and |<thin air| ',
        '<',
        0,
      ));
    });

    test('an unclosed think block leaves no answer and a thinking count', () {
      // The count is in characters, as the native client counts: été is three.
      expect(_split(<String>['<think>', 'the log says été 🐈', ' </thi']), (
        '',
        '',
        '<think>the log says été 🐈 </thi'.runes.length,
      ));
    });

    test('thinking a server sends apart is counted with the block\'s', () {
      final splitter = ThinkingSplitter()..count('hm, été');
      expect(splitter.push('<think>x</think>Twice.'), 'Twice.');
      expect(splitter.thinkingChars, 7 + '<think>x</think>'.length);
    });

    test(
      'a reply cut into single characters gives the answer of the whole reply',
      () {
        for (final reply in <String>[
          '',
          'plain words',
          '<think>hm été</think>\n\nTwice.',
          'a < b <thin air <think>x</think> c </think> d<',
          '<think>never closed </thi',
          '<<think>><</think>>',
          '<think>one</think>two<think>three</think>four',
          'hm, cats</think>\n\nTwice.',
          '<think>a</think> \n b </think>\n c d',
        ]) {
          expect(
            _answer(reply.split('')),
            _answer(<String>[reply]),
            reason: reply,
          );
        }
      },
    );
  });
}
