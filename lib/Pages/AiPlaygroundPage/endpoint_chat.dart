import 'dart:async';
import 'dart:convert';

import 'package:omni_accelerant/Pages/AiPlaygroundPage/endpoint_reply.dart';
import 'package:omni_accelerant/Pages/AiPlaygroundPage/endpoint_request.dart';
import 'package:omni_accelerant/Pages/AiPlaygroundPage/playground_settings.dart';
import 'package:omni_accelerant/src/rust/api/text.dart';

/// An endpoint's answer to a POST: its status, and its body's bytes as they arrive.
typedef EndpointReply = ({int status, Stream<List<int>> body});

/// POSTs [body] to [url]; a body stops reading at once when its listener leaves, and fails or closes when [cancel] completes.
typedef EndpointPost = Future<EndpointReply> Function(
  String url,
  Map<String, String> headers,
  String body, {
  required Future<void> cancel,
});

/// The native client's limit for a whole request; here each silence gets it, so a long streamed answer is not cut.
const Duration endpointPatience = Duration(seconds: 300);

/// As much of an error body as the native client keeps.
const int _errorBodyLimit = 2000;

/// The native client's bound on one line of a reply: past it the line is no answer this client reads.
const int endpointLineLimit = 1 << 20;

const Utf8Decoder _utf8 = Utf8Decoder(allowMalformed: true);

const String _thinkingOff = 'switch thinking off at the endpoint';

/// One request's end: the user's Stop, a silence that lasted too long, or the reply's own end.
class _Run {
  final Completer<void> _over = Completer<void>();

  /// Whether the user ended it, which is an answer marked as stopped and no failure.
  bool cancelled = false;

  Future<void> get over => _over.future;

  void end({bool byUser = false}) {
    if (_over.isCompleted) return;
    cancelled = byUser;
    _over.complete();
  }
}

/// One reply's answer as it builds up: what the user may read, and the figures of its `done`.
class _Answer {
  _Answer(this._now) : _start = _now();

  final DateTime Function() _now;
  final DateTime _start;
  final ReplyReader _reader = ReplyReader();
  final ThinkingSplitter _thinking = ThinkingSplitter();

  /// A blank start, held back so a reply that never says a word leaves no bubble.
  String _blank = '';
  bool _spoke = false;

  /// Whether the server said that nothing follows.
  bool ended = false;
  String? _finish;
  ({int prompt, int completion})? _usage;
  int _pieces = 0;
  DateTime? _first;

  /// The text [line] lets the user read now.
  String line(String line) => _take(_reader.line(line));

  /// The text held back until the reply ended; a reply without a finish reason or without words is a failure.
  String end() {
    final rest = _take(_reader.end()) + _visible(_thinking.finish());
    if (_finish == null) {
      throw const EndpointFailure('the stream ended without a finish reason');
    }
    if (!_spoke) throw EndpointFailure(_noAnswer());
    return rest;
  }

  String _take(ReplyPart? part) {
    if (part == null) return '';
    // Thinking is a piece too: the first one ends the wait for the first token.
    if (part.thinking.isNotEmpty || part.text.isNotEmpty) {
      _pieces++;
      _first ??= _now();
    }
    _thinking.count(part.thinking);
    _finish = part.finish ?? _finish;
    _usage = part.usage ?? _usage;
    ended = ended || part.done;
    return _visible(_answerIn(part.text));
  }

  /// The answer in [text]; a late close made all before it thinking, so the answer has not said a word yet.
  String _answerIn(String text) {
    final late = _thinking.lateCloses;
    final answer = _thinking.push(text);
    if (_thinking.lateCloses > late) {
      _blank = '';
      _spoke = false;
    }
    return answer;
  }

  String _visible(String text) {
    if (_spoke) return text;
    _blank += text;
    if (_blank.trim().isEmpty) return '';
    _spoke = true;
    return _blank;
  }

  /// A server without usage reports leaves the piece count of a stream, and nothing for a whole answer.
  int? get _completion =>
      _usage?.completion ?? (_reader.streamed ? _pieces : null);

  String _noAnswer() {
    final why = 'the model gave no answer (finish_reason $_finish)';
    final chars = _thinking.thinkingChars;
    if (chars == 0) return why;
    final tokens = _completion == null ? '' : ', $_completion tokens';
    // A model that ended by itself had budget left: a larger one is no way out.
    final (what, wayOut) = _finish == 'length'
        ? (
            'it spent its budget thinking',
            'set a larger maximum of new tokens or $_thinkingOff',
          )
        : ('it only thought', _thinkingOff);
    return '$why: $what ($chars characters of thinking$tokens); $wayOut';
  }

  /// The reply's `done`; a whole answer arrives at once, so it has no decode rate.
  TextEvent done() {
    final end = _now();
    final first = _first ?? end;
    return TextEvent(
      kind: 'done',
      finishReason: _finish,
      promptTokens: _usage?.prompt,
      completionTokens: _completion,
      timeToFirstTokenMs: first.difference(_start).inMicroseconds / 1000,
      decodeTokensPerSecond: _reader.streamed
          ? _decodeRate(_completion ?? 0, end.difference(first))
          : 0,
    );
  }
}

/// Tokens per second after the first one, which the wait for it already paid for.
double _decodeRate(int tokens, Duration decoding) =>
    tokens < 2 || decoding <= Duration.zero
    ? 0
    : (tokens - 1) * 1e6 / decoding.inMicroseconds;

/// The web build's chat client: one answer at a time over [post], read as its body arrives.
class EndpointChat {
  EndpointChat(
    this.post, {
    this.patience = endpointPatience,
    this.now = DateTime.now,
  });

  final EndpointPost post;

  /// How long the endpoint may stay silent, before its first byte and between two.
  final Duration patience;

  /// The clock the figures are read from; a test sets its own.
  final DateTime Function() now;
  _Run? _running;

  /// One chat completion as the bridge's events: `piece`s, then one `done`; a failure is a stream error.
  Stream<TextEvent> complete(
    PlaygroundSettings settings,
    List<TextMessage> messages,
  ) async* {
    final request = jsonEncode(chatCompletionBody(settings, messages));
    final run = _running = _Run();
    final answer = _Answer(now);
    var answered = false;
    try {
      final reply = await _post(settings, request, run);
      answered = true;
      await for (final line in await _lines(reply)) {
        final text = answer.line(line);
        if (text.isNotEmpty) yield TextEvent(kind: 'piece', text: text);
        if (answer.ended) break;
      }
      final rest = answer.end();
      if (rest.isNotEmpty) yield TextEvent(kind: 'piece', text: rest);
      yield answer.done();
    } on Object catch (failure) {
      if (!run.cancelled) throw _failure(failure, settings, answered: answered);
      yield const TextEvent(kind: 'done', finishReason: 'cancelled');
    } finally {
      run.end();
    }
  }

  /// Ends the running answer, whose stream closes with a `cancelled` `done`.
  void cancel() => _running?.end(byUser: true);

  Future<EndpointReply> _post(
    PlaygroundSettings settings,
    String request,
    _Run run,
  ) => post(
    '${settings.baseUrl}/v1/chat/completions',
    <String, String>{
      'content-type': 'application/json',
      if (settings.apiKey.isNotEmpty)
        'authorization': 'Bearer ${settings.apiKey}',
    },
    request,
    cancel: run.over,
  ).timeout(patience);

  /// The lines of a successful reply; any other status fails with the start of its body, the server's reason.
  Future<Stream<String>> _lines(EndpointReply reply) async {
    final body = reply.body.timeout(patience);
    if (reply.status >= 200 && reply.status < 300) {
      return const LineSplitter().bind(_utf8.bind(_boundedLines(body)));
    }
    final bytes = <int>[];
    await for (final chunk in body) {
      bytes.addAll(chunk);
      if (bytes.length >= _errorBodyLimit) break;
    }
    final reason = _utf8.convert(bytes.take(_errorBodyLimit).toList()).trim();
    throw EndpointFailure(
      'the endpoint answered HTTP ${reply.status}${reason.isEmpty ? '' : ': $reason'}',
    );
  }

  /// The body's bytes as they come, until one line grows past [endpointLineLimit] before its newline.
  static Stream<List<int>> _boundedLines(Stream<List<int>> body) async* {
    var line = 0;
    await for (final chunk in body) {
      var start = 0;
      for (
        var at = chunk.indexOf(0x0A);
        at >= 0;
        at = chunk.indexOf(0x0A, start)
      ) {
        if (line + at - start > endpointLineLimit) throw _overlong();
        line = 0;
        start = at + 1;
      }
      line += chunk.length - start;
      if (line > endpointLineLimit) throw _overlong();
      yield chunk;
    }
  }

  static EndpointFailure _overlong() => const EndpointFailure(
    'the endpoint sent a line over 1 MiB, the limit this client and the native one keep',
  );

  EndpointFailure _failure(
    Object failure,
    PlaygroundSettings settings, {
    required bool answered,
  }) => switch (failure) {
    EndpointFailure() => failure,
    TimeoutException() => EndpointFailure(
      'the endpoint at ${settings.baseUrl} sent nothing for ${patience.inSeconds} s',
    ),
    _ when answered => EndpointFailure(
      'the endpoint at ${settings.baseUrl} broke off its answer: $failure',
    ),
    _ => EndpointFailure('the endpoint at ${settings.baseUrl} is unreachable'),
  };
}
