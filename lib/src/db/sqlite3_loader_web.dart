import 'package:sqlite3/wasm.dart';

WasmSqlite3? _sqlite;
IndexedDbFileSystem? _fileSystem;
bool _vfsRegistered = false;

/// Loads sqlite3.wasm with an IndexedDB-backed VFS; throws [StateError] if either is unavailable.
Future<CommonSqlite3> loadSqlite3Impl() async {
  try {
    _sqlite ??= await WasmSqlite3.loadFromUrl(Uri.parse('sqlite3.wasm'));
  } catch (e) {
    throw StateError(
      'Failed to load SQLite3 WASM. Ensure sqlite3.wasm exists at /web/sqlite3.wasm. '
      'Error: $e',
    );
  }

  try {
    // Only register once; repeated registrations would throw.
    _fileSystem ??= await IndexedDbFileSystem.open(
      dbName: 'kataglyphis_inference_engine',
    );
    if (!_vfsRegistered) {
      _sqlite!.registerVirtualFileSystem(_fileSystem!, makeDefault: true);
      _vfsRegistered = true;
    }
  } catch (e) {
    throw StateError(
      'Failed to initialize IndexedDB file system for SQLite. '
      'Ensure IndexedDB is available in your browser. Error: $e',
    );
  }

  return _sqlite!;
}
