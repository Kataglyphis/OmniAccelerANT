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
    this.seed,
    this.jsonSchema = '',
    this.stop = const <String>[],
  });

  /// Restores what [toJson] wrote; a missing field keeps its default, a mistyped one throws [FormatException].
  factory PlaygroundSettings.fromJson(Map<String, Object?> json) {
    const d = PlaygroundSettings();
    final kindName = _read<String>(json, 'kind', d.kind.name);
    final kind = PlaygroundSourceKind.values.where((k) => k.name == kindName);
    if (kind.isEmpty) {
      throw FormatException('unknown playground source kind: $kindName');
    }
    return PlaygroundSettings(
      kind: kind.single,
      modelDir: _read(json, 'modelDir', d.modelDir),
      provider: _read(json, 'provider', d.provider),
      baseUrl: _read(json, 'baseUrl', d.baseUrl),
      model: _read(json, 'model', d.model),
      systemPrompt: _read(json, 'systemPrompt', d.systemPrompt),
      maxNewTokens: _read(json, 'maxNewTokens', d.maxNewTokens),
      temperature: _read<num>(json, 'temperature', d.temperature).toDouble(),
      seed: _read<int?>(json, 'seed', null),
      jsonSchema: _read(json, 'jsonSchema', d.jsonSchema),
      stop: <String>[
        for (final s in _read<List<Object?>>(json, 'stop', const <Object?>[]))
          if (s is String) s else throw FormatException('a stop string is $s'),
      ],
    );
  }

  final PlaygroundSourceKind kind;

  /// A GenAI model directory, for [PlaygroundSourceKind.local].
  final String modelDir;

  /// `cpu`, `cuda` or `dml`, for [PlaygroundSourceKind.local].
  final String provider;
  final String baseUrl;
  final String model;

  /// Held in memory only: [toJson] leaves it out, so no saved file carries it.
  final String apiKey;
  final String systemPrompt;
  final int maxNewTokens;

  /// 0 decodes greedily.
  final double temperature;

  /// Repeats a sampled answer; null draws a fresh one each time.
  final int? seed;

  /// A JSON schema the answer must follow; empty for free text.
  final String jsonSchema;

  /// Strings that end the answer; the answer excludes them.
  final List<String> stop;

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
    int? seed,
    bool clearSeed = false,
    String? jsonSchema,
    List<String>? stop,
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
    seed: clearSeed ? null : seed ?? this.seed,
    jsonSchema: jsonSchema ?? this.jsonSchema,
    stop: stop ?? this.stop,
  );

  /// Everything but [apiKey], which stays out of every store.
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.name,
    'modelDir': modelDir,
    'provider': provider,
    'baseUrl': baseUrl,
    'model': model,
    'systemPrompt': systemPrompt,
    'maxNewTokens': maxNewTokens,
    'temperature': temperature,
    'seed': seed,
    'jsonSchema': jsonSchema,
    'stop': stop,
  };

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
    stop: const <String>[],
  );
}

T _read<T>(Map<String, Object?> json, String key, T fallback) {
  if (!json.containsKey(key)) return fallback;
  final value = json[key];
  if (value is T) return value;
  throw FormatException('playground setting $key is $value, not a $T');
}
