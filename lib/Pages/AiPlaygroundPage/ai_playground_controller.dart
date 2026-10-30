import 'dart:async';

import 'package:anthology/Widgets/Chat/chat_entry.dart';
import 'package:flutter/foundation.dart';
import 'package:omni_accelerant/Pages/AiPlaygroundPage/playground_settings.dart';
import 'package:omni_accelerant/Pages/AiPlaygroundPage/text_client.dart';
import 'package:omni_accelerant/src/rust/api/text.dart';

/// The figures a `done` event carries, as the chat widgets show them.
ChatFigures figuresOf(TextEvent done) => ChatFigures(
  completionTokens: done.completionTokens ?? 0,
  timeToFirstTokenMs: done.timeToFirstTokenMs ?? 0,
  decodeTokensPerSecond: done.decodeTokensPerSecond ?? 0,
  finish: switch (done.finishReason) {
    'length' => ChatFinish.length,
    'cancelled' => ChatFinish.cancelled,
    _ => ChatFinish.stop,
  },
);

/// One conversation with a language model: its messages, the running answer and the settings it uses.
class AiPlaygroundController extends ChangeNotifier {
  AiPlaygroundController({TextClient? client})
    : client = client ?? const DefaultTextClient();

  final TextClient client;
  PlaygroundSettings settings = const PlaygroundSettings();
  final List<ChatEntry> _messages = <ChatEntry>[];
  StreamSubscription<TextEvent>? _run;
  bool busy = false;

  /// The last failure, cleared by the next message.
  String? error;

  List<ChatEntry> get messages => List<ChatEntry>.unmodifiable(_messages);

  void updateSettings(PlaygroundSettings next) {
    settings = next;
    notifyListeners();
  }

  /// Sends [text] with the whole conversation before it; a second send waits for the running answer.
  void send(String text) {
    if (busy) return;
    final history = <TextMessage>[
      if (settings.systemPrompt.isNotEmpty)
        TextMessage(role: 'system', content: settings.systemPrompt),
      for (final m in _messages)
        TextMessage(role: m.role.name, content: m.text),
      TextMessage(role: 'user', content: text),
    ];
    _messages
      ..add(ChatEntry(role: ChatRole.user, text: text))
      ..add(
        const ChatEntry(role: ChatRole.assistant, text: '', streaming: true),
      );
    busy = true;
    error = null;
    notifyListeners();
    _run = client
        .generate(settings, history)
        .listen(_onEvent, onError: _onError, onDone: _finish);
  }

  /// Ends the running answer after its current token.
  void stop() {
    if (busy) client.cancel();
  }

  void clear() {
    stop();
    _run?.cancel();
    _messages.clear();
    busy = false;
    error = null;
    notifyListeners();
  }

  void _onEvent(TextEvent event) {
    final last = _messages.last;
    if (event.kind == 'piece') {
      _messages.last = last.copyWith(text: last.text + (event.text ?? ''));
    } else if (event.kind == 'done') {
      _messages.last = last.copyWith(
        streaming: false,
        figures: figuresOf(event),
      );
    }
    notifyListeners();
  }

  void _onError(Object failure) {
    error = '$failure';
    if (_messages.isNotEmpty && _messages.last.text.isEmpty) {
      _messages.removeLast();
    }
    _finish();
  }

  void _finish() {
    if (!busy) return;
    busy = false;
    final last = _messages.last;
    if (last.role == ChatRole.assistant && last.streaming) {
      _messages.last = last.copyWith(streaming: false);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    _run?.cancel();
    super.dispose();
  }
}
