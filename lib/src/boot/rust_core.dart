import 'package:flutter/foundation.dart';

/// Whether the Rust core loaded; on the web the app can run without it.
bool get rustCoreAvailable => _rustCoreAvailable;
bool _rustCoreAvailable = false;

/// Runs [init]; an [optional] core that fails is logged and skipped, a required one rethrows.
Future<bool> loadRustCore(
  Future<void> Function() init, {
  required bool optional,
}) async {
  try {
    await init();
    _rustCoreAvailable = true;
  } catch (error) {
    _rustCoreAvailable = false;
    if (!optional) rethrow;
    debugPrint('Rust core not loaded, continuing without it: $error');
  }
  return _rustCoreAvailable;
}
