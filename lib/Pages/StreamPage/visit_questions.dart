import 'dart:async';

import 'package:anthology/Widgets/Chat/chat_panel.dart';
import 'package:flutter/material.dart';

import 'package:omni_accelerant/l10n/app_localizations.dart';
import 'package:omni_accelerant/Pages/StreamPage/observant_health.dart';
import 'package:omni_accelerant/utils/json_utils.dart';

/// ObservANT's answer to a POST: its status and body; `null` when none came.
typedef VisitQuestionPost = Future<({int status, String body})?> Function(
  String path,
  Map<String, Object> body, {
  Future<void>? cancel,
});

/// Why the last question got no answer: the camera's own words, or none when it stayed silent.
@immutable
class VisitQuestionFailure {
  const VisitQuestionFailure(this.reason);

  /// `null` when no reply came at all.
  final String? reason;
}

String? _text(Object? value) => value is String ? value : null;

/// Questions to ObservANT's `/ask` and `/summary`; it holds one conversation for the panel.
class VisitQuestionsController extends ChangeNotifier {
  VisitQuestionsController({
    required this.post,
    required this.language,
    this.now = DateTime.now,
  });

  final VisitQuestionPost post;

  /// The app's language, which ObservANT asks the model to answer in; it takes `de` and `en`.
  /// The panel outlives a language change, so it sets this before each build.
  String language;

  /// The clock whose offset says which local day "today" is; a test sets its own.
  final DateTime Function() now;

  final List<ChatEntry> _messages = <ChatEntry>[];
  Completer<void>? _cancel;
  bool _disposed = false;

  List<ChatEntry> get messages => List<ChatEntry>.unmodifiable(_messages);
  bool get busy => _cancel != null;

  /// What the model was told for the last answer.
  String? facts;
  VisitQuestionFailure? failure;

  Map<String, Object> _context() => <String, Object>{
    'tz_offset_min': now().timeZoneOffset.inMinutes,
    if (language == 'de' || language == 'en') 'language': language,
  };

  /// Asks one question; ignored while another runs.
  Future<void> ask(String question) => _run(
    question,
    '/ask',
    <String, Object>{'question': question, ..._context()},
    (json) {
      facts = _text(json['facts']);
      return _text(json['answer']);
    },
  );

  /// Asks for today's summary under [title]; a day without visits gets no model's words.
  Future<void> summarise(String title, String noVisits) => _run(
    title,
    '/summary',
    _context(),
    (json) => json['summary'] == null ? noVisits : _text(json['summary']),
  );

  Future<void> _run(
    String shown,
    String path,
    Map<String, Object> body,
    String? Function(Map<String, dynamic> json) read,
  ) async {
    if (busy) return;
    final cancel = _cancel = Completer<void>();
    failure = null;
    // The facts of an earlier answer say nothing about this one.
    facts = null;
    _messages
      ..add(ChatEntry(role: ChatRole.user, text: shown))
      ..add(
        const ChatEntry(role: ChatRole.assistant, text: '', streaming: true),
      );
    notifyListeners();
    final reply = await post(path, body, cancel: cancel.future);
    if (cancel.isCompleted) {
      _end(null);
    } else if (reply == null) {
      failure = const VisitQuestionFailure(null);
      _end(null);
    } else if (reply.status != 200) {
      failure = VisitQuestionFailure(reply.body);
      _end(null);
    } else {
      _answered(reply.body, read);
    }
  }

  void _answered(
    String body,
    String? Function(Map<String, dynamic> json) read,
  ) {
    final json = decodeJsonObject(body);
    final answer = json == null ? null : read(json);
    if (answer == null) {
      failure = VisitQuestionFailure(body);
    } else if (answer.trim().isEmpty) {
      // A model that spent its budget thinking answers 200 with no text; an empty bubble would pass as an answer.
      failure = VisitQuestionFailure(
        'the model gave no answer (finish_reason: ${json?['finish_reason']})',
      );
      facts = null;
      _end(null);
      return;
    }
    _end(answer);
  }

  void _end(String? answer) {
    // The page was left while the camera still answered; a disposed notifier must not notify.
    if (_disposed) return;
    _cancel = null;
    _messages.removeLast();
    if (answer != null) {
      _messages.add(ChatEntry(role: ChatRole.assistant, text: answer));
    }
    notifyListeners();
  }

  /// Leaves the running answer: the closed connection cancels it on the camera.
  void stop() {
    final cancel = _cancel;
    if (cancel != null && !cancel.isCompleted) {
      cancel.complete();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Offers questions about the visits when the camera's `/healthz` says a language model answers them.
class VisitQuestionsPanel extends StatefulWidget {
  const VisitQuestionsPanel({
    super.key,
    required this.fetchHealth,
    required this.post,
    this.now = DateTime.now,
  });

  /// `/healthz`'s body, or `null` when it does not answer.
  final Future<String?> Function() fetchHealth;
  final VisitQuestionPost post;
  final DateTime Function() now;

  @override
  State<VisitQuestionsPanel> createState() => _VisitQuestionsPanelState();
}

class _VisitQuestionsPanelState extends State<VisitQuestionsPanel> {
  bool _available = false;
  bool _open = false;
  VisitQuestionsController? _controller;

  /// False while another tab of the bottom bar shows: go_router keeps this page alive behind it.
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    unawaited(_probe());
  }

  Future<void> _probe() async {
    final body = await fetchOrNull(widget.fetchHealth);
    final answers = ObservantHealth.parse(body)?.answersQuestions ?? false;
    if (mounted && answers) {
      setState(() => _available = true);
    }
  }

  void _toggle() {
    _controller ??= VisitQuestionsController(
      post: widget.post,
      language: Localizations.localeOf(context).languageCode,
      now: widget.now,
    )..addListener(_changed);
    setState(() => _open = !_open);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _controller?.stop();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible && !_visible && !_available) {
      // Back in view: a camera that had no language model at the first look may have one now.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_probe());
        }
      });
    }
    _visible = visible;
    if (!_available) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context)!;
    _controller?.language = Localizations.localeOf(context).languageCode;
    final button = TextButton.icon(
      onPressed: _toggle,
      icon: Icon(_open ? Icons.expand_less : Icons.question_answer_outlined),
      label: Text(l10n.visitQuestions),
    );
    final controller = _controller;
    if (!_open || controller == null) {
      return button;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        button,
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: _QuestionsBody(controller: controller),
            ),
          ),
        ),
      ],
    );
  }
}

class _QuestionsBody extends StatelessWidget {
  const _QuestionsBody({required this.controller});

  final VisitQuestionsController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final failure = controller.failure;
    final facts = controller.facts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        Text(l10n.visitQuestionsHint, style: theme.textTheme.bodySmall),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton(
            onPressed: controller.busy
                ? null
                : () => unawaited(
                    controller.summarise(
                      l10n.visitQuestionsSummarise,
                      l10n.visitQuestionsNoVisits,
                    ),
                  ),
            child: Text(l10n.visitQuestionsSummarise),
          ),
        ),
        SizedBox(
          height: 320,
          child: ChatPanel(
            messages: controller.messages,
            busy: controller.busy,
            onSend: (text) => unawaited(controller.ask(text)),
            onStop: controller.stop,
          ),
        ),
        if (failure != null)
          Text(
            failure.reason == null
                ? l10n.visitQuestionsUnreachable
                : l10n.visitQuestionsFailed(failure.reason!),
            style: TextStyle(color: theme.colorScheme.error),
          ),
        if (facts != null)
          ExpansionTile(
            title: Text(l10n.visitQuestionsFacts),
            children: [SelectableText(facts)],
          ),
      ],
    );
  }
}
