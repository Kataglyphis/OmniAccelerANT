import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The channel all three platform plugins answer on.
const String kNativeInferenceChannelName = 'kataglyphis_native_inference';

/// A platform whose plugin answers on [kNativeInferenceChannelName].
enum PluginPlatform { android, linux, windows }

/// One method of the channel: what it takes, what it answers, and which error codes each platform sends.
class PluginMethod {
  const PluginMethod(
    this.name, {
    required this.arguments,
    required this.result,
    required this.errors,
  });

  final String name;
  final String arguments;
  final String result;

  /// Error codes per platform; a platform missing here answers "not implemented".
  final Map<PluginPlatform, List<String>> errors;

  Iterable<PluginPlatform> get platforms => errors.keys;
}

/// The channel's whole API; `test/plugin_channel_test.dart` holds it against the Kotlin, Linux and Windows handlers.
const List<PluginMethod> kNativeInferenceMethods = <PluginMethod>[
  PluginMethod(
    'getPlatformVersion',
    arguments: 'none',
    result: 'String',
    errors: {
      PluginPlatform.android: [],
      PluginPlatform.linux: [],
      PluginPlatform.windows: [],
    },
  ),
  PluginMethod(
    'add',
    arguments: "{'a': int, 'b': int}",
    result: 'int',
    errors: {
      PluginPlatform.windows: ['bad_args'],
    },
  ),
  PluginMethod(
    'create',
    arguments: '[width, height]',
    result: 'int texture id; a second create answers the first id',
    errors: {
      PluginPlatform.android: ['no_controller', 'bad_args', 'create_failed'],
      PluginPlatform.linux: ['bad_args', 'create_failed'],
      PluginPlatform.windows: ['bad_args', 'create_failed'],
    },
  ),
  PluginMethod(
    'hasPushedFrame',
    arguments: 'none',
    result: 'bool',
    errors: {PluginPlatform.linux: []},
  ),
  PluginMethod(
    'setPipeline',
    arguments: 'String launch line',
    result: 'null',
    errors: {
      PluginPlatform.android: ['bad_args', 'no_controller', 'command_failed'],
    },
  ),
  PluginMethod(
    'play',
    arguments: 'none',
    result: 'null',
    errors: {
      PluginPlatform.android: ['no_controller', 'command_failed'],
    },
  ),
  PluginMethod(
    'pause',
    arguments: 'none',
    result: 'null',
    errors: {
      PluginPlatform.android: ['no_controller', 'command_failed'],
    },
  ),
  PluginMethod(
    'stop',
    arguments: 'none',
    result: 'null',
    errors: {
      PluginPlatform.android: ['no_controller', 'command_failed'],
    },
  ),
  PluginMethod(
    'diagnose',
    arguments: 'none',
    result: 'String',
    errors: {
      PluginPlatform.android: ['no_controller', 'command_failed'],
    },
  ),
  PluginMethod(
    'setColor',
    arguments: '[r, g, b]',
    result: 'null',
    errors: {
      PluginPlatform.android: ['bad_args', 'no_controller', 'command_failed'],
      PluginPlatform.windows: ['no_texture', 'bad_args'],
    },
  ),
];

/// The platform this build's plugin runs on, or null on web and where no plugin is registered.
PluginPlatform? currentPluginPlatform() {
  if (kIsWeb) return null;
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => PluginPlatform.android,
    TargetPlatform.linux => PluginPlatform.linux,
    TargetPlatform.windows => PluginPlatform.windows,
    _ => null,
  };
}

/// Whether [platform]'s plugin answers [method].
bool pluginAnswers(String method, PluginPlatform? platform) =>
    kNativeInferenceMethods.any(
      (m) => m.name == method && m.errors.containsKey(platform),
    );

/// Typed calls on the channel; app code calls these instead of naming methods.
abstract final class NativeInferenceChannel {
  static const MethodChannel channel = MethodChannel(
    kNativeInferenceChannelName,
  );

  static Future<String?> getPlatformVersion() =>
      channel.invokeMethod<String>('getPlatformVersion');

  static Future<int> add(int a, int b) async =>
      await channel.invokeMethod<int>('add', {'a': a, 'b': b}) ?? 0;

  static Future<int?> create(int width, int height) =>
      channel.invokeMethod<int>('create', <int>[width, height]);

  static Future<bool> hasPushedFrame() async =>
      await channel.invokeMethod<bool>('hasPushedFrame') ?? false;

  static Future<void> setPipeline(String launchLine) =>
      channel.invokeMethod<void>('setPipeline', launchLine);

  static Future<void> play() => channel.invokeMethod<void>('play');

  static Future<void> pause() => channel.invokeMethod<void>('pause');

  static Future<void> stop() => channel.invokeMethod<void>('stop');

  static Future<String?> diagnose() => channel.invokeMethod<String>('diagnose');

  static Future<void> setColor(int r, int g, int b) =>
      channel.invokeMethod<void>('setColor', <int>[r, g, b]);
}
