import 'package:anthology/Layout/ResponsiveDesign/single_page.dart';
import 'package:anthology/Pages/Footer/footer.dart';
import 'package:anthology/Widgets/Chat/chat_panel.dart';
import 'package:anthology/app_attributes.dart';
import 'package:flutter/material.dart';
import 'package:omni_accelerant/Pages/AiPlaygroundPage/ai_playground_controller.dart';
import 'package:omni_accelerant/Pages/AiPlaygroundPage/playground_settings.dart';
import 'package:omni_accelerant/l10n/app_localizations.dart';

/// Chat with a language model: the chain GenAI in this process on Linux and Windows, or any OpenAI-compatible endpoint.
class AiPlaygroundPage extends StatefulWidget {
  const AiPlaygroundPage({
    super.key,
    required this.appAttributes,
    required this.footer,
    this.controller,
  });

  final AppAttributes appAttributes;
  final Footer footer;

  /// Injected by widget tests; production owns its controller.
  final AiPlaygroundController? controller;

  @override
  State<AiPlaygroundPage> createState() => _AiPlaygroundPageState();
}

class _AiPlaygroundPageState extends State<AiPlaygroundPage> {
  late final AiPlaygroundController _controller =
      widget.controller ?? AiPlaygroundController();

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SinglePage(
    footer: widget.footer,
    appAttributes: widget.appAttributes,
    showMediumSizeLayout: widget.appAttributes.showMediumSizeLayout,
    showLargeSizeLayout: widget.appAttributes.showLargeSizeLayout,
    children: <Widget>[
      Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: AiPlaygroundView(controller: _controller),
          ),
        ),
      ),
    ],
  );
}

/// The settings above the conversation; [AiPlaygroundPage] puts it in the app's page frame.
class AiPlaygroundView extends StatelessWidget {
  const AiPlaygroundView({super.key, required this.controller});

  final AiPlaygroundController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            l10n.aiPlaygroundTitle,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          ExpansionTile(
            title: Text(l10n.aiSettings),
            children: <Widget>[PlaygroundSettingsForm(controller: controller)],
          ),
          if (controller.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                l10n.aiError(controller.error!),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          SizedBox(
            height: 520,
            child: Card(
              child: ChatPanel(
                messages: controller.messages,
                onSend: controller.send,
                onStop: controller.stop,
                busy: controller.busy,
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: controller.messages.isEmpty ? null : controller.clear,
              icon: const Icon(Icons.restart_alt),
              label: Text(l10n.aiClear),
            ),
          ),
        ],
      ),
    );
  }
}

/// The source and generation settings; each change applies to the next message.
class PlaygroundSettingsForm extends StatelessWidget {
  const PlaygroundSettingsForm({super.key, required this.controller});

  final AiPlaygroundController controller;

  void _set(PlaygroundSettings next) => controller.updateSettings(next);

  Widget _field(
    String label,
    String value,
    ValueChanged<String> changed, {
    bool secret = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: TextFormField(
      initialValue: value,
      obscureText: secret,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      onChanged: changed,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final s = controller.settings;
    final local = controller.client.localAvailable;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SegmentedButton<PlaygroundSourceKind>(
            segments: <ButtonSegment<PlaygroundSourceKind>>[
              ButtonSegment(
                value: PlaygroundSourceKind.endpoint,
                label: Text(l10n.aiSourceEndpoint),
              ),
              ButtonSegment(
                value: PlaygroundSourceKind.local,
                label: Text(l10n.aiSourceLocal),
                enabled: local,
              ),
            ],
            selected: <PlaygroundSourceKind>{s.kind},
            onSelectionChanged: (kinds) => _set(s.copyWith(kind: kinds.first)),
          ),
          if (!local)
            Text(
              l10n.aiLocalUnavailable,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (s.kind == PlaygroundSourceKind.local) ...<Widget>[
            _field(
              l10n.aiModelDir,
              s.modelDir,
              (v) => _set(s.copyWith(modelDir: v)),
            ),
            DropdownButtonFormField<String>(
              initialValue: s.provider,
              decoration: InputDecoration(labelText: l10n.aiProvider),
              items: const <DropdownMenuItem<String>>[
                DropdownMenuItem(value: 'cpu', child: Text('CPU')),
                DropdownMenuItem(value: 'cuda', child: Text('CUDA')),
                DropdownMenuItem(value: 'dml', child: Text('DirectML')),
              ],
              onChanged: (v) => _set(s.copyWith(provider: v)),
            ),
          ] else ...<Widget>[
            _field(
              l10n.aiBaseUrl,
              s.baseUrl,
              (v) => _set(s.copyWith(baseUrl: v.trim())),
            ),
            _field(
              l10n.aiModel,
              s.model,
              (v) => _set(s.copyWith(model: v.trim())),
            ),
            _field(
              l10n.aiApiKey,
              s.apiKey,
              (v) => _set(s.copyWith(apiKey: v)),
              secret: true,
            ),
          ],
          _field(
            l10n.aiSystemPrompt,
            s.systemPrompt,
            (v) => _set(s.copyWith(systemPrompt: v)),
          ),
          _field(
            l10n.aiMaxTokens,
            '${s.maxNewTokens}',
            (v) => _set(
              s.copyWith(maxNewTokens: int.tryParse(v) ?? s.maxNewTokens),
            ),
          ),
          Text('${l10n.aiTemperature}: ${s.temperature.toStringAsFixed(2)}'),
          Slider(
            value: s.temperature,
            max: 1.5,
            divisions: 30,
            onChanged: (v) => _set(s.copyWith(temperature: v)),
          ),
        ],
      ),
    );
  }
}
