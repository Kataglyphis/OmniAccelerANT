import 'dart:convert';

import 'package:omni_accelerant/Pages/AiPlaygroundPage/playground_settings.dart';
import 'package:omni_accelerant/Pages/AiPlaygroundPage/playground_settings_store_io.dart'
    if (dart.library.js_interop) 'package:omni_accelerant/Pages/AiPlaygroundPage/playground_settings_store_web.dart'
    as platform;

/// Where the playground keeps its settings between runs; the API key never reaches it.
abstract class PlaygroundSettingsStore {
  /// The saved settings, or null when nothing was saved yet.
  Future<PlaygroundSettings?> load();

  Future<void> save(PlaygroundSettings settings);
}

/// A JSON file in the app's support directory on native builds; the browser's local storage on the web.
PlaygroundSettingsStore defaultPlaygroundSettingsStore() =>
    platform.defaultStore();

/// The one encoding every store writes, so no store can carry the key.
String encodePlaygroundSettings(PlaygroundSettings settings) =>
    jsonEncode(settings.toJson());

PlaygroundSettings decodePlaygroundSettings(String text) {
  final json = jsonDecode(text);
  if (json is! Map<String, Object?>) {
    throw FormatException('saved playground settings are not an object: $text');
  }
  return PlaygroundSettings.fromJson(json);
}
