import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sqlite3/common.dart';

import 'sqlite3_loader.dart';

Future<String> runSqliteHealthcheck() async {
  final CommonSqlite3 sqlite = await loadSqlite3();

  // IndexedDB-backed on the web; in-memory natively, so no writable directory must be picked.
  final CommonDatabase db = kIsWeb
      ? sqlite.open('/kataglyphis.db')
      : sqlite.openInMemory();

  try {
    db.execute(
      'CREATE TABLE IF NOT EXISTS healthcheck (id INTEGER PRIMARY KEY AUTOINCREMENT, created_at TEXT NOT NULL);',
    );

    db.execute(
      "INSERT INTO healthcheck (created_at) VALUES (datetime('now'));",
    );

    final ResultSet rows = db.select('SELECT COUNT(*) AS c FROM healthcheck;');
    final count = rows.first['c'];

    return kIsWeb
        ? 'OK (Web persistent, rows=$count)'
        : 'OK (Native in-memory, rows=$count)';
  } finally {
    db.close();
  }
}
