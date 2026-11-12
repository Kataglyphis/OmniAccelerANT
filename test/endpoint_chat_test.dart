// The web build's chat client against a fake endpoint; the fetch half is `web_endpoint_test.dart`, in Chrome.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_accelerant/Pages/AiPlaygroundPage/ai_playground_controller.dart';
import 'package:omni_accelerant/Pages/AiPlaygroundPage/endpoint_chat.dart';
import 'package:omni_accelerant/Pages/AiPlaygroundPage/endpoint_reply.dart';
import 'package:omni_accelerant/Pages/AiPlaygroundPage/endpoint_request.dart';
import 'package:omni_accelerant/Pages/AiPlaygroundPage/playground_settings.dart';
import 'package:omni_accelerant/Pages/AiPlaygroundPage/text_client.dart';
import 'package:omni_accelerant/src/rust/api/text.dart';

typedef _Posted = ({String url, Map<String, String> headers, String body});

/// Records what the client posted and answers with [status] and the body a test hands it.
class _Endpoint {
  _Endpoint({this.status = 200, this.answers = true});

  final int status;

  /// False for an endpoint that takes the request and never answers it.
  final bool answers;
  final List<_Posted> posted = <_Posted>[];
  final StreamController<List<int>> body = StreamController<List<int>>();
  final Completer<EndpointReply> _reply = Completer<EndpointReply>();

  bool _over = false;

  /// Whether the client gave the request up or was done with it, which it says a moment after its stream ends.
  Future<bool> get over async {
    await pumpEventQueue();
    return _over;
  }

  Future<EndpointReply> post(
    String url,
    Map<String, String> headers,
    String body, {
    required Future<void> cancel,
  }) {
    posted.add((url: url, headers: headers, body: body));
    unawaited(cancel.then((_) => _abort()));
    if (answers) _reply.complete((status: status, body: this.body.stream));
    return _reply.future;
  }

  /// As an aborted fetch does: the waiting request and the open body both fail.
  void _abort() {
    _over = true;
    if (!_reply.isCompleted) _reply.completeError(StateError('aborted'));
    if (!body.isClosed) {
      body.addError(StateError('aborted'));
      unawaited(body.close());
    }
  }

  void send(String text) => body.add(utf8.encode(text));

  /// Sends [chunks] and ends the body.
  void finish(List<String> chunks) {
    chunks.forEach(send);
    unawaited(body.close());
  }
}

/// An endpoint whose whole reply is [chunks].
_Endpoint _answering(List<String> chunks, {int status = 200}) =>
    _Endpoint(status: status)..finish(chunks);

class _Clock {
  DateTime at = DateTime(2026, 11, 12, 12);

  DateTime now() => at;

  void pass(int milliseconds) =>
      at = at.add(Duration(milliseconds: milliseconds));
}

/// The playground's client as the web build wires it, over [chat].
class _WebClient implements TextClient {
  _WebClient(this.chat);

  final EndpointChat chat;

  @override
  bool get localAvailable => false;

  @override
  Stream<TextEvent> generate(
    PlaygroundSettings settings,
    List<TextMessage> messages,
  ) => chat.complete(settings, messages);

  @override
  void cancel() => chat.cancel();
}

const PlaygroundSettings _settings = PlaygroundSettings();
const String _base = 'http://127.0.0.1:18200';
const List<TextMessage> _hi = <TextMessage>[
  TextMessage(role: 'user', content: 'How often?'),
];
const Duration _short = Duration(milliseconds: 40);
const TextEvent _cancelled = TextEvent(kind: 'done', finishReason: 'cancelled');

String _data(Map<String, Object?> chunk) => 'data: ${jsonEncode(chunk)}\n\n';

/// One stream line with [delta] and, at the reply's end, its [finish] reason.
String _delta(Map<String, Object?> delta, {String? finish}) =>
    _data(<String, Object?>{
      'choices': <Object?>[
        <String, Object?>{'index': 0, 'delta': delta, 'finish_reason': finish},
      ],
    });

String _text(String content) => _delta(<String, Object?>{'content': content});

String _end(String finish) => _delta(<String, Object?>{}, finish: finish);

String _usage(int prompt, int completion) => _data(<String, Object?>{
  'choices': <Object?>[],
  'usage': <String, Object?>{
    'prompt_tokens': prompt,
    'completion_tokens': completion,
  },
});

const String _done = 'data: [DONE]\n\n';

/// A whole, non-streamed answer with [message].
String _whole(
  Map<String, Object?> message, {
  String finish = 'stop',
  int? completion,
}) => jsonEncode(<String, Object?>{
  'choices': <Object?>[
    <String, Object?>{'index': 0, 'message': message, 'finish_reason': finish},
  ],
  if (completion != null)
    'usage': <String, Object?>{
      'prompt_tokens': 9,
      'completion_tokens': completion,
    },
});

TextEvent _piece(String text) => TextEvent(kind: 'piece', text: text);

/// What an answer's stream gave: its events, and the failure that ended it.
Future<(List<TextEvent>, Object?)> _collect(Stream<TextEvent> answer) async {
  final events = <TextEvent>[];
  try {
    await for (final event in answer) {
      events.add(event);
    }
  } on Object catch (failure) {
    return (events, failure);
  }
  return (events, null);
}

/// The events and the failure of one request to [endpoint].
Future<(List<TextEvent>, Object?)> _ask(
  _Endpoint endpoint, {
  Duration patience = endpointPatience,
}) => _collect(
  EndpointChat(endpoint.post, patience: patience).complete(_settings, _hi),
);

/// What the user reads of [events].
String _shown(List<TextEvent> events) =>
    events.where((e) => e.kind == 'piece').map((e) => e.text).join();

Matcher _failure(Object reason) =>
    isA<EndpointFailure>().having((f) => f.reason, 'reason', reason);

void main() {
  group('the request', () {
    test('the chat body is POSTed to /v1/chat/completions', () async {
      final endpoint = _answering(<String>[
        _whole(<String, Object?>{'content': 'Twice.'}),
      ]);
      final (_, failure) = await _ask(endpoint);
      expect(failure, isNull);
      final posted = endpoint.posted.single;
      expect(posted.url, '$_base/v1/chat/completions');
      expect(posted.headers, <String, String>{
        'content-type': 'application/json',
      });
      expect(jsonDecode(posted.body), chatCompletionBody(_settings, _hi));
      // The transport hears that the client is done, so it can let the connection go.
      expect(await endpoint.over, isTrue);
    });

    test(
      'a key is sent as a bearer token, to the base URL of the settings',
      () async {
        final endpoint = _answering(<String>[
          _whole(<String, Object?>{'content': 'Twice.'}),
        ]);
        await _collect(
          EndpointChat(endpoint.post).complete(
            _settings.copyWith(baseUrl: 'http://lan:11434', apiKey: 'k'),
            _hi,
          ),
        );
        final posted = endpoint.posted.single;
        expect(posted.url, 'http://lan:11434/v1/chat/completions');
        expect(posted.headers['authorization'], 'Bearer k');
      },
    );

    test(
      'a schema that is no JSON object fails before anything is sent',
      () async {
        final endpoint = _Endpoint();
        final (events, failure) = await _collect(
          EndpointChat(endpoint.post)
              .complete(_settings.copyWith(jsonSchema: '[]'), _hi),
        );
        expect(events, isEmpty);
        expect(failure, isFormatException);
        expect(endpoint.posted, isEmpty);
      },
    );

    test('the limit for a silence is the native client\'s 300 s', () {
      expect(
        EndpointChat(_Endpoint().post).patience,
        const Duration(seconds: 300),
      );
    });
  });

  group('a whole answer', () {
    test(
      'it is one piece, and its done has the usage and no decode rate',
      () async {
        final endpoint = _Endpoint();
        final clock = _Clock();
        final answer = _collect(
          EndpointChat(endpoint.post, now: clock.now).complete(_settings, _hi),
        );
        await pumpEventQueue();
        clock.pass(1500);
        endpoint.finish(<String>[
          _whole(<String, Object?>{'content': 'Twice.'}, completion: 3),
        ]);
        final (events, failure) = await answer;
        expect(failure, isNull);
        expect(events, <TextEvent>[
          _piece('Twice.'),
          const TextEvent(
            kind: 'done',
            finishReason: 'stop',
            promptTokens: 9,
            completionTokens: 3,
            timeToFirstTokenMs: 1500,
            decodeTokensPerSecond: 0,
          ),
        ]);
      },
    );

    test('without a usage report it claims no token count', () async {
      final (events, _) = await _ask(
        _answering(<String>[
          _whole(<String, Object?>{'content': 'Twice.'}, finish: 'length'),
        ]),
      );
      expect(events.last.finishReason, 'length');
      expect(events.last.completionTokens, isNull);
    });

    test(
      'an error inside a 200 answer fails with the server\'s words',
      () async {
        for (final body in <String>[
          '{"error":{"message":"model gone","type":"server_error"}}',
          '{"error":"model gone"}',
        ]) {
          final (events, failure) = await _ask(_answering(<String>[body]));
          expect(events, isEmpty, reason: body);
          expect(failure, _failure('model gone'), reason: body);
        }
      },
    );

    test('an answer without choices, or one that is no JSON, is a failure that shows it', () async {
      final (_, empty) = await _ask(_answering(<String>['{"choices":[]}']));
      expect(
        empty,
        _failure("the endpoint's answer has no choices: {\"choices\":[]}"),
      );
      final (_, page) = await _ask(_answering(<String>['<html>', '</html>']));
      expect(
        page,
        _failure("the endpoint's answer is no chat reply: <html></html>"),
      );
      final (_, nothing) = await _ask(_answering(<String>[]));
      expect(
        nothing,
        _failure("the endpoint's answer is no chat reply: it is empty"),
      );
    });
  });

  group('a streamed answer', () {
    test(
      'it arrives piece by piece, with figures read from the clock',
      () async {
        final endpoint = _Endpoint();
        final clock = _Clock();
        final events = <TextEvent>[];
        final ended = EndpointChat(
          endpoint.post,
          now: clock.now,
        ).complete(_settings, _hi).forEach(events.add);
        await pumpEventQueue();
        clock.pass(200);
        endpoint.send(_text('Twi'));
        await pumpEventQueue();
        expect(events, <TextEvent>[_piece('Twi')]);
        clock.pass(500);
        endpoint.finish(<String>[
          _text('ce.'),
          _end('stop'),
          _usage(9, 6),
          _done,
        ]);
        await ended;
        expect(events, <TextEvent>[
          _piece('Twi'),
          _piece('ce.'),
          const TextEvent(
            kind: 'done',
            finishReason: 'stop',
            promptTokens: 9,
            completionTokens: 6,
            timeToFirstTokenMs: 200,
            decodeTokensPerSecond: 10,
          ),
        ]);
      },
    );

    test(
      'without a usage report its pieces are counted, thinking too',
      () async {
        final (events, failure) = await _ask(
          _answering(<String>[
            _delta(<String, Object?>{'reasoning_content': 'hm'}),
            _text('Twi'),
            _text('ce.'),
            _end('length'),
            _done,
          ]),
        );
        expect(failure, isNull);
        expect(events.last.finishReason, 'length');
        expect(events.last.completionTokens, 3);
        expect(events.last.promptTokens, isNull);
      },
    );

    test('lines may end in CR LF and be cut anywhere, also inside a character', () async {
      final bytes = utf8.encode(
        '${_text('été 🐈').trimRight()}\r\n\r\n${_end('stop').trimRight()}\r\n',
      );
      final endpoint = _Endpoint();
      for (final byte in bytes) {
        endpoint.body.add(<int>[byte]);
      }
      unawaited(endpoint.body.close());
      final (events, failure) = await _ask(endpoint);
      expect(failure, isNull);
      expect(_shown(events), 'été 🐈');
    });

    test(
      'it ends at [DONE] though the server keeps the connection open',
      () async {
        final endpoint = _Endpoint()
          ..send(_text('Twice.'))
          ..send(_end('stop'))
          ..send(_done);
        final (events, failure) = await _ask(endpoint);
        expect(failure, isNull);
        expect(_shown(events), 'Twice.');
        expect(events.last.finishReason, 'stop');
        expect(await endpoint.over, isTrue);
      },
    );

    test('an error line ends the answer with the server\'s words', () async {
      for (final line in <String>[
        'data: {"error":{"message":"model gone"}}\n\n',
        'data: {"error":"model gone"}\n\n',
      ]) {
        // The body stays open: the failure must not wait for the server to hang up.
        final endpoint = _Endpoint()
          ..send(_text('Tw'))
          ..send(line);
        final (events, failure) = await _ask(endpoint);
        expect(events, <TextEvent>[_piece('Tw')], reason: line);
        expect(failure, _failure('model gone'), reason: line);
        expect(await endpoint.over, isTrue, reason: line);
      }
    });

    test('a stream that ends without a finish reason is a failure', () async {
      final (events, failure) = await _ask(_answering(<String>[_text('Tw')]));
      expect(events, <TextEvent>[_piece('Tw')]);
      expect(failure, _failure('the stream ended without a finish reason'));
    });
  });

  group('thinking', () {
    test('thinking in either field is never shown', () async {
      for (final name in <String>['reasoning_content', 'reasoning']) {
        final (events, failure) = await _ask(
          _answering(<String>[
            _delta(<String, Object?>{name: 'Okay, the log', 'content': ''}),
            _delta(<String, Object?>{name: ' says two.', 'content': null}),
            _text('Twice.'),
            _end('stop'),
            _done,
          ]),
        );
        expect(failure, isNull, reason: name);
        expect(_shown(events), 'Twice.', reason: name);
      }
      final (events, _) = await _ask(
        _answering(<String>[
          _whole(<String, Object?>{
            'content': 'Twice.',
            'reasoning_content': 'Okay, the log says two.',
          }),
        ]),
      );
      expect(_shown(events), 'Twice.');
    });

    test('a think block in the text is cut out, also with its tag split over chunks', () async {
      final (streamed, _) = await _ask(
        _answering(<String>[
          _text('<thi'),
          _text('nk>Okay, the log says two.</th'),
          _text('ink>Twice.'),
          _end('stop'),
          _done,
        ]),
      );
      expect(_shown(streamed), 'Twice.');
      final (whole, _) = await _ask(
        _answering(<String>[
          _whole(<String, Object?>{
            'content': '<think>Okay, the log says two.</think>Twice.',
          }),
        ]),
      );
      expect(_shown(whole), 'Twice.');
    });

    test('a blank start is held back until a word follows', () async {
      final (events, _) = await _ask(
        _answering(<String>[
          _delta(<String, Object?>{'reasoning_content': 'hm'}),
          _text('\n'),
          _text('\n'),
          _text('Twice.'),
          _end('stop'),
          _done,
        ]),
      );
      expect(events.where((e) => e.kind == 'piece'), <TextEvent>[
        _piece('\n\nTwice.'),
      ]);
    });

    test('the white space after a think block is not shown', () async {
      final (streamed, _) = await _ask(
        _answering(<String>[
          _text('<think>hm</think>'),
          _text('\n'),
          _text('\n'),
          _text('Twice.\n'),
          _end('stop'),
          _done,
        ]),
      );
      expect(_shown(streamed), 'Twice.\n');
      final (whole, _) = await _ask(
        _answering(<String>[
          _whole(<String, Object?>{'content': '<think>hm</think>\n\nTwice.'}),
        ]),
      );
      expect(_shown(whole), 'Twice.');
    });

    test('a closing tag alone makes the text before it thinking', () async {
      // A whole answer shows nothing of it.
      final (whole, _) = await _ask(
        _answering(<String>[
          _whole(<String, Object?>{
            'content': 'Okay, the log says two.\n</think>\n\nTwice.',
          }),
        ]),
      );
      expect(whole.where((e) => e.kind == 'piece'), <TextEvent>[
        _piece('Twice.'),
      ]);
      // A stream has shown the start by then, and the answer follows it.
      final (streamed, failure) = await _ask(
        _answering(<String>[
          _text('Okay'),
          _text('</think>'),
          _text('\n\n'),
          _text('Twice.'),
          _end('stop'),
          _done,
        ]),
      );
      expect(failure, isNull);
      expect(_shown(streamed), 'OkayTwice.');
    });

    test(
      'a reply that ends at a closing tag alone has given no answer',
      () async {
        final (whole, noWords) = await _ask(
          _answering(<String>[
            _whole(<String, Object?>{
              'content': 'Okay</think>',
            }, finish: 'length'),
          ]),
        );
        expect(whole, isEmpty);
        expect(
          noWords,
          _failure(contains('it spent its budget thinking (12 characters')),
        );
        final (streamed, cut) = await _ask(
          _answering(<String>[
            _text('Okay'),
            _text('</think>'),
            _text('\n'),
            _end('length'),
            _done,
          ]),
        );
        expect(streamed, <TextEvent>[_piece('Okay')]);
        expect(
          cut,
          _failure(
            contains(
              'it spent its budget thinking (12 characters of thinking, 3 tokens)',
            ),
          ),
        );
      },
    );

    test('a reply that was only thinking is a failure that says so, not an empty answer', () async {
      const hint =
          'set a larger maximum of new tokens or switch thinking off at the endpoint';
      final replies = <(List<String>, String)>[
        // The server sends the thinking apart and the budget ends inside it.
        (
          <String>[
            _delta(<String, Object?>{'reasoning_content': 'Okay, '}),
            _delta(<String, Object?>{'reasoning_content': 'the log'}),
            _end('length'),
            _usage(9, 128),
            _done,
          ],
          '13 characters of thinking, 128 tokens',
        ),
        // The thinking is in the text and its block never closes; without usage the pieces are the count.
        (
          <String>[_text('<think>'), _text('the log'), _end('length'), _done],
          '14 characters of thinking, 2 tokens',
        ),
        // A whole answer whose content is null beside its thinking.
        (
          <String>[
            _whole(
              <String, Object?>{'content': null, 'reasoning_content': 'Okay'},
              finish: 'length',
              completion: 128,
            ),
          ],
          '4 characters of thinking, 128 tokens',
        ),
        // A whole answer cut inside its block, from a server that reports no usage.
        (
          <String>[
            _whole(<String, Object?>{
              'content': '<think>Okay',
            }, finish: 'length'),
          ],
          '11 characters of thinking',
        ),
      ];
      for (final (chunks, counted) in replies) {
        final (events, failure) = await _ask(_answering(chunks));
        expect(events, isEmpty, reason: counted);
        expect(
          failure,
          _failure(
            'the model gave no answer (finish_reason length): '
            'it spent its budget thinking ($counted); $hint',
          ),
          reason: counted,
        );
      }
    });

    test('a model that only thought and ended by itself is not told to raise the budget', () async {
      final replies = <(List<String>, int)>[
        (
          <String>[
            _delta(<String, Object?>{'reasoning_content': 'Okay'}),
            _end('stop'),
            _usage(9, 7),
            _done,
          ],
          4,
        ),
        (
          <String>[
            _whole(<String, Object?>{
              'content': '<think>hm</think>',
            }, completion: 7),
          ],
          17,
        ),
      ];
      for (final (chunks, chars) in replies) {
        final (events, failure) = await _ask(_answering(chunks));
        expect(events, isEmpty, reason: '$chars');
        expect(
          failure,
          _failure(
            'the model gave no answer (finish_reason stop): it only thought '
            '($chars characters of thinking, 7 tokens); switch thinking off at the endpoint',
          ),
          reason: '$chars',
        );
      }
    });

    test(
      'a reply without words and without thinking is a failure too',
      () async {
        for (final chunks in <List<String>>[
          <String>[
            _whole(<String, Object?>{'content': null}),
          ],
          <String>[
            _whole(<String, Object?>{'content': ' \n'}),
          ],
          <String>[_text('\n'), _end('stop'), _done],
        ]) {
          final (events, failure) = await _ask(_answering(chunks));
          expect(events, isEmpty, reason: '$chunks');
          expect(
            failure,
            _failure('the model gave no answer (finish_reason stop)'),
            reason: '$chunks',
          );
        }
      },
    );
  });

  group('a server that refuses or stays silent', () {
    test(
      'a status that is no success keeps the server\'s body as the reason',
      () async {
        final (events, busy) = await _ask(
          _answering(<String>['the model ', 'is loading\n'], status: 503),
        );
        expect(events, isEmpty);
        expect(
          busy,
          _failure('the endpoint answered HTTP 503: the model is loading'),
        );
        const json = '{"error":{"message":"model \'x\' not found"}}';
        final (_, missing) = await _ask(
          _answering(<String>[json], status: 404),
        );
        expect(missing, _failure('the endpoint answered HTTP 404: $json'));
        final (_, bare) = await _ask(_answering(<String>[], status: 502));
        expect(bare, _failure('the endpoint answered HTTP 502'));
      },
    );

    test('a long error body is cut where the native client cuts it', () async {
      final (_, failure) = await _ask(
        _answering(<String>['x' * 1500, 'y' * 1500], status: 500),
      );
      expect(
        failure,
        _failure('the endpoint answered HTTP 500: ${'x' * 1500}${'y' * 500}'),
      );
    });

    test(
      'an endpoint that never answers fails after the limit and is given up',
      () async {
        final endpoint = _Endpoint(answers: false);
        final (events, failure) = await _ask(endpoint, patience: _short);
        expect(events, isEmpty);
        expect(
          failure,
          _failure(startsWith('the endpoint at $_base sent nothing for ')),
        );
        expect(await endpoint.over, isTrue);
      },
    );

    test(
      'an endpoint that falls silent inside its answer fails after the limit',
      () async {
        final endpoint = _Endpoint()..send(_text('Tw'));
        final (events, failure) = await _ask(endpoint, patience: _short);
        expect(events, <TextEvent>[_piece('Tw')]);
        expect(
          failure,
          _failure(startsWith('the endpoint at $_base sent nothing for ')),
        );
        expect(await endpoint.over, isTrue);
      },
    );

    test('an error body that never ends fails after the limit', () async {
      final endpoint = _Endpoint(status: 503)..send('the model');
      final (_, failure) = await _ask(endpoint, patience: _short);
      expect(
        failure,
        _failure(startsWith('the endpoint at $_base sent nothing for ')),
      );
    });

    test(
      'a request that cannot be sent says the endpoint is unreachable',
      () async {
        final chat = EndpointChat(
          (url, headers, body, {required cancel}) =>
              Future<EndpointReply>.error(StateError('Failed to fetch')),
        );
        final (events, failure) = await _collect(chat.complete(_settings, _hi));
        expect(events, isEmpty);
        expect(failure, _failure('the endpoint at $_base is unreachable'));
      },
    );

    test('an answer that breaks off says so, after the text that came', () async {
      final endpoint = _Endpoint()
        ..send(_text('Tw'))
        ..body.addError(StateError('network changed'));
      final (events, failure) = await _ask(endpoint);
      expect(events, <TextEvent>[_piece('Tw')]);
      expect(
        failure,
        _failure(
          'the endpoint at $_base broke off its answer: Bad state: network changed',
        ),
      );
    });
  });

  group('Stop', () {
    test('a waiting request ends as cancelled, not as a failure', () async {
      final endpoint = _Endpoint(answers: false);
      final chat = EndpointChat(endpoint.post);
      final answer = _collect(chat.complete(_settings, _hi));
      await pumpEventQueue();
      chat.cancel();
      final (events, failure) = await answer;
      expect(failure, isNull);
      expect(events, <TextEvent>[_cancelled]);
      expect(await endpoint.over, isTrue);
    });

    test(
      'an answer stopped inside its body keeps its text and ends as cancelled',
      () async {
        final endpoint = _Endpoint()..send(_text('Tw'));
        final chat = EndpointChat(endpoint.post);
        final answer = _collect(chat.complete(_settings, _hi));
        await pumpEventQueue();
        chat.cancel();
        final (events, failure) = await answer;
        expect(failure, isNull);
        expect(events, <TextEvent>[_piece('Tw'), _cancelled]);
      },
    );

    test('after a Stop the next answer is read as usual', () async {
      final first = _Endpoint(answers: false);
      final second = _answering(<String>[
        _whole(<String, Object?>{'content': 'Twice.'}),
      ]);
      final endpoints = <_Endpoint>[first, second];
      final chat = EndpointChat(
        (url, headers, body, {required cancel}) =>
            endpoints.removeAt(0).post(url, headers, body, cancel: cancel),
      );
      final stopped = _collect(chat.complete(_settings, _hi));
      await pumpEventQueue();
      chat.cancel();
      expect((await stopped).$1, <TextEvent>[_cancelled]);
      final (events, failure) = await _collect(chat.complete(_settings, _hi));
      expect(failure, isNull);
      expect(_shown(events), 'Twice.');
      expect(events.last.finishReason, 'stop');
    });

    test('a Stop with nothing running does nothing', () async {
      final chat = EndpointChat(
        _answering(<String>[
          _whole(<String, Object?>{'content': 'Twice.'}),
        ]).post,
      )..cancel();
      final (events, failure) = await _collect(chat.complete(_settings, _hi));
      expect(failure, isNull);
      expect(_shown(events), 'Twice.');
    });
  });

  group('the playground on this client', () {
    test(
      'a model that only thought shows the reason and no empty answer',
      () async {
        final playground = AiPlaygroundController(
          client: _WebClient(
            EndpointChat(
              _answering(<String>[
                _delta(<String, Object?>{'reasoning': 'Okay'}),
                _end('length'),
                _done,
              ]).post,
            ),
          ),
        )..send('How often?');
        addTearDown(playground.dispose);
        await pumpEventQueue();
        expect(playground.busy, isFalse);
        expect(playground.messages.map((m) => m.text), <String>['How often?']);
        expect(playground.error, contains('it spent its budget thinking'));
      },
    );

    test('a server\'s error is shown in its own words alone', () async {
      final playground = AiPlaygroundController(
        client: _WebClient(
          EndpointChat(
            _answering(<String>['{"error":{"message":"model gone"}}']).post,
          ),
        ),
      )..send('How often?');
      addTearDown(playground.dispose);
      await pumpEventQueue();
      expect(playground.error, 'model gone');
      expect(playground.messages, hasLength(1));
    });
  });
}
