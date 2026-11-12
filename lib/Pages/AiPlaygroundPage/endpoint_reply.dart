import 'dart:convert';
import 'dart:math';

/// A reply that failed; it prints as the reason alone, the way the bridge's failures read.
class EndpointFailure implements Exception {
  const EndpointFailure(this.reason);

  /// The server's own words where it sent any.
  final String reason;

  @override
  String toString() => reason;
}

/// What one stream line or one whole answer carries; `finish` is `stop` or `length`, and `done` says nothing follows.
typedef ReplyPart = ({
  String thinking,
  String text,
  String? finish,
  ({int prompt, int completion})? usage,
  bool done,
});

/// As much of a broken reply as the native client keeps of an error body.
const int _shownChars = 2000;

/// What a `data:` line of a streamed chat carries; `null` for any other line.
ReplyPart? parseStreamLine(String line) {
  if (!line.startsWith('data:')) return null;
  final data = line.substring('data:'.length).trim();
  if (data == '[DONE]') {
    return (thinking: '', text: '', finish: null, usage: null, done: true);
  }
  return _part(_object(data, 'an unreadable stream chunk'), 'delta');
}

/// What a whole, non-streamed chat answer carries; one without a choice is a failure.
ReplyPart parseWholeAnswer(String body) {
  final answer = _object(body.trim(), "the endpoint's answer is no chat reply");
  final part = _part(answer, 'message');
  if (_firstChoice(answer) == null) {
    throw EndpointFailure(
      "the endpoint's answer has no choices: ${_clip(body.trim())}",
    );
  }
  return (
    thinking: part.thinking,
    text: part.text,
    finish: part.finish ?? 'stop',
    usage: part.usage,
    done: true,
  );
}

String _clip(String text) => text.substring(0, min(text.length, _shownChars));

Map<String, dynamic> _object(String text, String what) {
  try {
    final Object? json = jsonDecode(text);
    if (json is Map<String, dynamic>) return json;
  } on FormatException {
    // A broken text and a text that is no object fail alike, below.
  }
  throw EndpointFailure('$what: ${text.isEmpty ? 'it is empty' : _clip(text)}');
}

/// The part in a chunk's `delta` or a whole answer's `message`, named by [key]; an error inside it is a failure.
ReplyPart _part(Map<String, dynamic> chunk, String key) {
  final failure = _errorWords(chunk['error']);
  if (failure != null) throw EndpointFailure(failure);
  final choice = _firstChoice(chunk);
  final Object? said = choice?[key];
  return (
    thinking: said is Map ? _thinking(said) : '',
    text: said is Map ? _string(said['content']) : '',
    finish: _finish(choice?['finish_reason']),
    usage: _usage(chunk['usage']),
    done: false,
  );
}

/// OpenAI nests the error's message; Ollama sends the error as the text itself.
String? _errorWords(Object? error) => switch (error) {
  null => null,
  final String words when words.isNotEmpty => words,
  {'message': final String words} when words.isNotEmpty => words,
  _ => jsonEncode(error),
};

Map<String, dynamic>? _firstChoice(Map<String, dynamic> chunk) {
  final Object? choices = chunk['choices'];
  final Object? first = choices is List && choices.isNotEmpty
      ? choices.first
      : null;
  return first is Map<String, dynamic> ? first : null;
}

/// llama-server and vLLM name the thinking `reasoning_content`, Ollama `reasoning`.
String _thinking(Map<dynamic, dynamic> said) {
  final named = _string(said['reasoning_content']);
  return named.isNotEmpty ? named : _string(said['reasoning']);
}

String _string(Object? value) => value is String ? value : '';

String? _finish(Object? reason) => switch (reason) {
  'length' => 'length',
  String() => 'stop',
  _ => null,
};

({int prompt, int completion})? _usage(Object? usage) => usage is Map
    ? (
        prompt: _count(usage['prompt_tokens']),
        completion: _count(usage['completion_tokens']),
      )
    : null;

int _count(Object? value) => value is num ? value.toInt() : 0;

/// Reads a reply line by line: `data:` lines as a stream, and a body without any as one whole answer.
class ReplyReader {
  final StringBuffer _whole = StringBuffer();

  /// Whether the reply came as `data:` lines.
  bool streamed = false;

  /// What [line] carries; `null` when it is no data line.
  ReplyPart? line(String line) {
    final part = parseStreamLine(line);
    if (part != null) {
      streamed = true;
      _whole.clear();
    } else if (!streamed) {
      _whole.writeln(line);
    }
    return part;
  }

  /// What the body carries as a whole answer once it ended; `null` after a stream, whose lines said it all.
  ReplyPart? end() => streamed ? null : parseWholeAnswer(_whole.toString());
}

/// Splits a reply's text into answer and thinking; a `<think>` block and its tags count as thinking.
class ThinkingSplitter {
  static const String _open = '<think>';
  static const String _close = '</think>';

  /// The end of the reply so far that may still begin a tag.
  String _pending = '';
  bool _inside = false;

  /// A block has just closed: the white space a model writes after it is not the answer's.
  bool _afterClose = false;

  /// Answer characters given out so far, which a closing tag without its opening one makes thinking.
  int _answerChars = 0;

  /// Characters that were thinking, the tags included.
  int thinkingChars = 0;

  /// Late closes: closing tags without their opening one, which the chat template wrote into the prompt.
  int lateCloses = 0;

  /// The answer text [piece] settles; thinking is counted and left out, and so is this piece's text before a late close.
  String push(String piece) {
    _pending += piece;
    final answer = StringBuffer();
    while (true) {
      final (at, tag) = _firstTag(
        _pending,
        _inside ? const <String>[_close] : const <String>[_open, _close],
      );
      final safe = tag == null ? _pending.length - _tagStart(_pending) : at;
      _settle(_pending.substring(0, safe), answer);
      if (tag == null) {
        _pending = _pending.substring(safe);
        _answerChars += answer.toString().runes.length;
        return answer.toString();
      }
      _pending = _pending.substring(safe + tag.length);
      _pass(tag, answer);
    }
  }

  void _settle(String settled, StringBuffer answer) {
    if (_inside) {
      count(settled);
      return;
    }
    final text = _afterClose ? settled.trimLeft() : settled;
    if (text.isEmpty) return;
    _afterClose = false;
    answer.write(text);
  }

  /// Counts [tag] and enters or leaves the block; a late close makes all answer before it thinking.
  void _pass(String tag, StringBuffer answer) {
    final closes = tag == _close;
    if (closes && !_inside) {
      lateCloses++;
      thinkingChars += _answerChars + answer.toString().runes.length;
      _answerChars = 0;
      answer.clear();
    }
    count(tag);
    _inside = !closes;
    _afterClose = closes;
  }

  /// Counts thinking, also what a server sends apart from the text.
  void count(String thinking) => thinkingChars += thinking.runes.length;

  /// What was held back when the reply ended: answer text, or thinking when the block never closed.
  String finish() {
    final answer = StringBuffer();
    _settle(_pending, answer);
    _pending = '';
    return answer.toString();
  }

  /// How many characters at the end of [text] may be the start of a tag.
  static int _tagStart(String text) {
    for (var held = min(_close.length - 1, text.length); held > 0; held--) {
      final end = text.substring(text.length - held);
      if (_open.startsWith(end) || _close.startsWith(end)) return held;
    }
    return 0;
  }
}

/// Where the first of [tags] begins in [text] and which one it is; -1 and null when none is there.
(int, String?) _firstTag(String text, List<String> tags) {
  (int, String?) first = (-1, null);
  for (final tag in tags) {
    final at = text.indexOf(tag);
    if (at >= 0 && (first.$2 == null || at < first.$1)) first = (at, tag);
  }
  return first;
}
