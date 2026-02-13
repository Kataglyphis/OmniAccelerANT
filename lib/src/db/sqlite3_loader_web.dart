import 'package:sqlite3/wasm.dart';

WasmSqlite3? _sqlite;
IndexedDbFileSystem? _fileSystem;
bool _vfsRegistered = false;

Future<CommonSqlite3> loadSqlite3Impl() async {
  _sqlite ??= await WasmSqlite3.loadFromUrl(Uri.parse('sqlite3.wasm'));

  // Only register once; repeated registrations would throw.
  _fileSystem ??= await IndexedDbFileSystem.open(
    dbName: 'kataglyphis_inference_engine',
  );
  if (!_vfsRegistered) {
    _sqlite!.registerVirtualFileSystem(_fileSystem!, makeDefault: true);
    _vfsRegistered = true;
  }

  return _sqlite!;
}
