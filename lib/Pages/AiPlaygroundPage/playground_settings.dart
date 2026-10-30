import 'package:omni_accelerant/src/rust/api/text.dart';

/// Where the playground's answers come from.
enum PlaygroundSourceKind { local, endpoint }

/// The playground's backend and generation settings; the defaults reach OrchestrANT's `orchestrant-serve`.
class PlaygroundSettings {
  const PlaygroundSettings({
    this.kind = PlaygroundSourceKind.endpoint,
    this.modelDir = '',
    this.provider = 'cpu',
    this.baseUrl = 'http://127.0.0.1:18200',
    this.model = 'smollm2_135m_instruct-cpu',
    this.apiKey = '',
    this.systemPrompt = '',
    this.maxNewTokens = 256,
    this.temperature = 0.0,
  });

  final PlaygroundSourceKind kind;

  /// A GenAI model directory, for [PlaygroundSourceKind.local].
  final String modelDir;

  /// `cpu`, `cuda` or `dml`, for [PlaygroundSourceKind.local].
  final String provider;
  final String baseUrl;
  final String model;
  final String apiKey;
  final String systemPrompt;
  final int maxNewTokens;

  /// 0 decodes greedily.
  final double temperature;

  PlaygroundSettings copyWith({
    PlaygroundSourceKind? kind,
    String? modelDir,
    String? provider,
    String? baseUrl,
    String? model,
    String? apiKey,
    String? systemPrompt,
    int? maxNewTokens,
    double? temperature,
  }) => PlaygroundSettings(
    kind: kind ?? this.kind,
    modelDir: modelDir ?? this.modelDir,
    provider: provider ?? this.provider,
    baseUrl: baseUrl ?? this.baseUrl,
    model: model ?? this.model,
    apiKey: apiKey ?? this.apiKey,
    systemPrompt: systemPrompt ?? this.systemPrompt,
    maxNewTokens: maxNewTokens ?? this.maxNewTokens,
    temperature: temperature ?? this.temperature,
  );

  /// The bridge's source: the model directory, or the endpoint with its model and key.
  TextSource source() => kind == PlaygroundSourceKind.local
      ? TextSource(modelDir: modelDir, provider: provider)
      : TextSource(
          provider: provider,
          baseUrl: baseUrl,
          model: model.isEmpty ? null : model,
          apiKey: apiKey.isEmpty ? null : apiKey,
        );

  TextOptions options() => TextOptions(
    maxNewTokens: maxNewTokens,
    temperature: temperature,
    topP: 1.0,
    topK: 50,
  );
}
