import 'dart:io';

import 'package:omni_accelerant/Pages/AiPlaygroundPage/playground_settings.dart';
import 'package:omni_accelerant/Pages/AiPlaygroundPage/playground_settings_store.dart';
import 'package:path_provider/path_provider.dart';

const String settingsFileName = 'ai_playground_settings.json';

/// Saves to `<dir>/ai_playground_settings.json`, the directory resolved at the first call.
class FilePlaygroundSettingsStore implements PlaygroundSettingsStore {
  FilePlaygroundSettingsStore(this.directory);

  final Future<Directory> Function() directory;

  Future<File> _file() async => File(
    '${(await directory()).path}${Platform.pathSeparator}$settingsFileName',
  );

  @override
  Future<PlaygroundSettings?> load() async {
    final file = await _file();
    if (!file.existsSync()) return null;
    return decodePlaygroundSettings(await file.readAsString());
  }

  @override
  Future<void> save(PlaygroundSettings settings) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    // A rename replaces the file whole, so a crash mid-write leaves the previous settings.
    final partial = File('${file.path}.partial');
    await partial.writeAsString(
      encodePlaygroundSettings(settings),
      flush: true,
    );
    await partial.rename(file.path);
  }
}

PlaygroundSettingsStore defaultStore() =>
    FilePlaygroundSettingsStore(getApplicationSupportDirectory);
