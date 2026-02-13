import 'package:sqlite3/common.dart';

import 'sqlite3_loader_native.dart'
    if (dart.library.js_interop) 'sqlite3_loader_web.dart';

Future<CommonSqlite3> loadSqlite3() => loadSqlite3Impl();
