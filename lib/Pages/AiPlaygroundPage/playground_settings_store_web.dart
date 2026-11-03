import 'package:omni_accelerant/Pages/AiPlaygroundPage/playground_settings.dart';
import 'package:omni_accelerant/Pages/AiPlaygroundPage/playground_settings_store.dart';
import 'package:web/web.dart' as web;

const String _key = 'omni_accelerant.ai_playground_settings';

/// The browser's local storage for this origin.
class LocalStoragePlaygroundSettingsStore implements PlaygroundSettingsStore {
  @override
  Future<PlaygroundSettings?> load() async {
    final text = web.window.localStorage.getItem(_key);
    return text == null ? null : decodePlaygroundSettings(text);
  }

  @override
  Future<void> save(PlaygroundSettings settings) async =>
      web.window.localStorage.setItem(_key, encodePlaygroundSettings(settings));
}

PlaygroundSettingsStore defaultStore() => LocalStoragePlaygroundSettingsStore();
